import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_tilt/flutter_tilt.dart';
import 'package:local_auth/local_auth.dart';
import 'package:card_scanner/card_scanner.dart';
import 'package:salomon_bottom_bar/salomon_bottom_bar.dart';
import 'package:horizontal_credit_card/horizontal_credit_card.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'theme/cardy_transitions.dart';
import 'data/local_database.dart';
import 'data/secure_card_data.dart';
import 'features/cards/credit_card.dart';
import 'features/cards/card_catalogue.dart';
import 'features/cards/card_catalogue_page.dart';
import 'features/assistant/ai_chat_page.dart';
import 'features/compare/compare_page.dart';
import 'features/cards/card_search_delegate.dart';
import 'theme/cardy_palette.dart';
import 'features/cards/card_number_boxes.dart';

String _groupCardNumber(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  final groups = <String>[];
  for (var i = 0; i < digits.length; i += 4) {
    groups.add(digits.substring(i, (i + 4).clamp(0, digits.length)));
  }
  return groups.join(' ');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CardyApp());
}

class CardyApp extends StatelessWidget {
  const CardyApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: cardyDarkMode,
        builder: (context, darkMode, child) => MaterialApp(
          title: 'Cardy',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF5F5F6),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF171719),
              primary: const Color(0xFF171719),
              secondary: const Color(0xFF55555C),
              brightness: Brightness.light,
              surface: Colors.white,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF5F5F6),
              foregroundColor: Color(0xFF171719),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE7E7E9)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: Color(0xFF303034), width: 1.4),
              ),
              hintStyle: const TextStyle(color: Color(0xFF77777E)),
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: Color(0xFF171719),
              foregroundColor: Colors.white,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF101113),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFF0F0F1),
              primary: const Color(0xFFF0F0F1),
              secondary: const Color(0xFFBFC0C3),
              brightness: Brightness.dark,
              surface: const Color(0xFF1C1D20),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF101113),
              foregroundColor: Color(0xFFF3F3F4),
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1C1D20),
              hintStyle: const TextStyle(color: Color(0xFFAAAAB0)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF35363A)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: Color(0xFFF0F0F1), width: 1.4),
              ),
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: Color(0xFFF0F0F1),
              foregroundColor: Color(0xFF171719),
            ),
          ),
          themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
          home: const CardyHome(),
        ),
      );
}

class CardyHome extends StatefulWidget {
  const CardyHome({super.key});
  @override
  State<CardyHome> createState() => _CardyHomeState();
}

class _CardyHomeState extends State<CardyHome> {
  final math.Random _styleRandom = math.Random.secure();
  final PageController _walletPageController =
      PageController(viewportFraction: .82);
  int tab = 0;
  bool loaded = false;
  Timer? _clipboardClearTimer;
  List<CreditCard> cards = [];
  String query = '';
  String _activeFilter = 'All';
  String? _bankFilter;
  String? _networkFilter;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _clipboardClearTimer?.cancel();
    _walletPageController.dispose();
    super.dispose();
  }

  void _resetWalletPage() {
    if (_walletPageController.hasClients) {
      _walletPageController.jumpToPage(0);
    }
  }

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      cardyDarkMode.value = preferences.getBool('dark_mode') ?? false;
      final database = await LocalDatabase.instance.database;
      var saved = (await database.query('cards', orderBy: 'id'))
          .map(CreditCard.fromDatabase)
          .toList();
      var removedLegacyCvv = false;
      for (final card in saved) {
        if (card.secureDetails.isNotEmpty) {
          try {
            final details = await SecureCardData.decrypt(card.secureDetails);
            card.cardNumber = details['number']!;
            card.expiryDate = details['expiry']!;
            // CVV values from earlier versions are deliberately discarded.
            if (details.containsKey('cvv')) {
              removedLegacyCvv = true;
              card.secureDetails =
                  card.cardNumber.isEmpty && card.expiryDate.isEmpty
                      ? ''
                      : await SecureCardData.encrypt(
                          number: card.cardNumber,
                          expiry: card.expiryDate,
                        );
              if (card.databaseId != null) {
                await database.update(
                  'cards',
                  {'secure_details': card.secureDetails},
                  where: 'id = ?',
                  whereArgs: [card.databaseId],
                );
              }
            }
          } catch (_) {
            // Keep the rest of the local card usable if secure data cannot be read.
          }
        }
      }
      if (removedLegacyCvv) {
        try {
          await database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        } catch (_) {
          // The platform may use a journal mode without WAL checkpoint support.
        }
      }
      if (saved.isEmpty) {
        final legacy = preferences.getString('cards');
        if (legacy != null) {
          saved = (jsonDecode(legacy) as List)
              .map((row) => CreditCard.fromJson(row as Map<String, dynamic>))
              .toList();
          for (final card in saved) {
            if (card.secureDetails.isEmpty) continue;
            try {
              final details = await SecureCardData.decrypt(card.secureDetails);
              card.cardNumber = details['number']!;
              card.expiryDate = details['expiry']!;
              card.cvv = '';
            } catch (error) {
              throw StateError(
                  'Could not migrate encrypted legacy card data: $error');
            }
          }
          await _replaceCardsInDatabase(database, saved);
          await preferences.remove('cards');
        }
      }
      for (final card in saved) {
        if (card.styleSeed >= 0) continue;
        card.styleSeed = _newCardStyleSeed();
        if (card.databaseId != null) {
          await database.update(
            'cards',
            {'style_seed': card.styleSeed},
            where: 'id = ?',
            whereArgs: [card.databaseId],
          );
        }
      }
      if (!mounted) return;
      setState(() {
        cards = saved;
        loaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => loaded = true);
      _info('Could not open local database',
          'Cardy could not read its on-device database. Details: $error');
    }
  }

  Future<void> _persistCard(CreditCard card, {bool notify = true}) async {
    final database = await LocalDatabase.instance.database;
    if (card.cardNumber.isNotEmpty || card.expiryDate.isNotEmpty) {
      card.secureDetails = await SecureCardData.encrypt(
        number: card.cardNumber,
        expiry: card.expiryDate,
      );
    } else {
      // Clear the encrypted blob too, so cleared fields cannot return later.
      card.secureDetails = '';
    }
    final row = card.toDatabase()..remove('id');
    if (card.databaseId == null) {
      card.databaseId = await database.insert('cards', row);
    } else {
      final updated = await database.update(
        'cards',
        row,
        where: 'id = ?',
        whereArgs: [card.databaseId],
      );
      if (updated == 0) throw StateError('The saved card no longer exists.');
    }
    if (notify && mounted) setState(() {});
  }

  int _newCardStyleSeed() => _styleRandom.nextInt(0x7fffffff);

  Future<void> _replaceCardsInDatabase(
    Database database,
    List<CreditCard> values,
  ) async {
    // Finish Android Keystore calls before opening SQLite's transaction. Keeping
    // a sqflite transaction open across a platform-channel call can invalidate
    // the transaction on some Android/plugin combinations.
    final rows = <Map<String, Object?>>[];
    for (final card in values) {
      if (card.cardNumber.isNotEmpty || card.expiryDate.isNotEmpty) {
        card.secureDetails = await SecureCardData.encrypt(
          number: card.cardNumber,
          expiry: card.expiryDate,
        );
      } else {
        card.secureDetails = '';
      }
      rows.add(card.toDatabase());
    }
    await database.transaction((txn) async {
      await txn.delete('cards');
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final id = await txn.insert('cards', row);
        values[i].databaseId = id;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['', 'My Cards', 'Compare', 'AI Assistant'];
    return Scaffold(
      appBar: tab == 0
          ? null
          : AppBar(
              title: Text(
                titles[tab],
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              actions: [
                IconButton(
                  onPressed: () => _search(),
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedSearch01),
                ),
              ],
            ),
      body: !loaded
          ? Center(child: CircularProgressIndicator(color: accentColor))
          : IndexedStack(
              index: tab,
              children: [_dashboard(), _myCards(), _compare(), _assistant()],
            ),
      floatingActionButton: tab == 1
          ? FloatingActionButton.extended(
              onPressed: _chooseAddCard,
              backgroundColor: accentColor,
              foregroundColor:
                  isCardyDarkMode ? const Color(0xFF111111) : Colors.white,
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01),
              label: const Text('Add card'),
            )
          : null,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Material(
            color: bottomBarBackground,
            elevation: 12,
            shadowColor: Colors.black.withValues(alpha: .24),
            borderRadius: BorderRadius.circular(26),
            clipBehavior: Clip.antiAlias,
            child: SalomonBottomBar(
              currentIndex: tab,
              onTap: (index) => setState(() => tab = index),
              backgroundColor: bottomBarBackground,
              selectedItemColor: bottomBarSelected,
              unselectedItemColor: bottomBarUnselected,
              selectedColorOpacity: .17,
              itemPadding:
                  const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
              margin: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
              items: [
                SalomonBottomBarItem(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedHome01),
                  activeIcon:
                      const HugeIcon(icon: HugeIcons.strokeRoundedHome02),
                  title: const Text('Home'),
                ),
                SalomonBottomBarItem(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedCreditCard),
                  title: const Text('My Cards'),
                ),
                SalomonBottomBarItem(
                  icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedChartIncrease),
                  title: const Text('Compare'),
                ),
                SalomonBottomBarItem(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedSparkles),
                  title: const Text('Assistant'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashboard() {
    final activeCards =
        cards.asMap().entries.where((entry) => entry.value.active).toList();
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning,'
        : hour < 18
            ? 'Good afternoon,'
            : 'Good evening,';
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(greeting, style: TextStyle(color: muted)),
                    const SizedBox(height: 2),
                    Text('Cardy',
                        style: TextStyle(
                            color: brandAccentDeep,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Search cards',
                onPressed: _search,
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedSearch01),
              ),
              IconButton(
                tooltip: 'Scan a card',
                onPressed: _scanCard,
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedScan),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: _openSettings,
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedSettings01),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            height: 142,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isCardyDarkMode
                    ? const [Color(0xFF393A3F), Color(0xFF1D1E21)]
                    : const [Color(0xFF3B3B40), Color(0xFF171719)],
              ),
              boxShadow: [
                BoxShadow(
                  color: brandAccent.withValues(alpha: .26),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(children: [
                Positioned(
                  right: -20,
                  top: -46,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: .13),
                          width: 24),
                    ),
                  ),
                ),
                Positioned(
                  right: 54,
                  bottom: -49,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: .08),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(19, 17, 19, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('YOUR WALLET',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .78),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.3,
                          )),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${activeCards.length}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 40,
                                  height: 1,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 9),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text('active cards',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('${cards.length} cards saved in your wallet',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: .78),
                              fontSize: 12)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              Expanded(
                  child: _quickAction(
                      HugeIcons.strokeRoundedAdd01, 'Add card', _editCard,
                      filled: true)),
              const SizedBox(width: 9),
              Expanded(
                  child: _quickAction(HugeIcons.strokeRoundedGlobe, 'Browse',
                      _browseCatalogue)),
              const SizedBox(width: 9),
              Expanded(
                  child: _quickAction(HugeIcons.strokeRoundedChartIncrease,
                      'Compare', () => setState(() => tab = 2))),
            ],
          ),
          if (_cardsExpiringSoon().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isCardyDarkMode
                    ? const Color(0xFF3B3021)
                    : const Color(0xFFFFF2D9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedCalendarOff,
                    color: isCardyDarkMode
                        ? const Color(0xFFFFC66D)
                        : const Color(0xFF8A5A00),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_cardsExpiringSoon().map((card) => card.nickname.isEmpty ? card.name : card.nickname).join(', ')} expiring within 3 months',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 27),
          _sectionTitle('Your Cards',
              action: 'See all', onTap: () => setState(() => tab = 1)),
          const SizedBox(height: 12),
          if (activeCards.isEmpty)
            _empty(
              'Add your first card',
              'Keep your card benefits together and compare rewards.',
              HugeIcons.strokeRoundedWallet01,
              button: 'Add a card',
              onTap: _editCard,
            )
          else
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: activeCards.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _cardTile(
                  activeCards[i].value,
                  width: 300,
                  styleSeed: activeCards[i].value.styleSeed,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _myCards() {
    final banks = cards
        .map((card) => card.bank)
        .where((bank) => bank.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final networks = cards
        .map((card) => card.network)
        .where((network) => network.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final filteredCards = cards.where((card) {
      final activityMatches = _activeFilter == 'All' ||
          (_activeFilter == 'Active' ? card.active : !card.active);
      return activityMatches &&
          (_bankFilter == null || card.bank == _bankFilter) &&
          (_networkFilter == null || card.network == _networkFilter);
    }).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      children: [
        const Text(
          'Your wallet',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          '${cards.length} saved ${cards.length == 1 ? 'card' : 'cards'} · Stored on this device',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: _activeFilter == 'All',
              onSelected: (_) {
                _resetWalletPage();
                setState(() => _activeFilter = 'All');
              },
            ),
            ChoiceChip(
              label: const Text('Active'),
              selected: _activeFilter == 'Active',
              onSelected: (_) {
                _resetWalletPage();
                setState(() => _activeFilter = 'Active');
              },
            ),
            ChoiceChip(
              label: const Text('Paused'),
              selected: _activeFilter == 'Paused',
              onSelected: (_) {
                _resetWalletPage();
                setState(() => _activeFilter = 'Paused');
              },
            ),
            if (banks.isNotEmpty)
              DropdownButton<String?>(
                value: _bankFilter,
                hint: const Text('Bank'),
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('All banks')),
                  ...banks.map((bank) => DropdownMenuItem<String?>(
                      value: bank, child: Text(bank))),
                ],
                onChanged: (value) {
                  _resetWalletPage();
                  setState(() => _bankFilter = value);
                },
              ),
            if (networks.isNotEmpty)
              DropdownButton<String?>(
                value: _networkFilter,
                hint: const Text('Network'),
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('All networks')),
                  ...networks.map((network) => DropdownMenuItem<String?>(
                      value: network, child: Text(network))),
                ],
                onChanged: (value) {
                  _resetWalletPage();
                  setState(() => _networkFilter = value);
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (cards.isEmpty)
          _empty(
            'Your cards will live here',
            'Browse the card catalogue or enter your card details manually.',
            HugeIcons.strokeRoundedCreditCard,
            button: 'Add your first card',
            onTap: _editCard,
          )
        else if (filteredCards.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
                child: Text('No cards match these filters.',
                    style: TextStyle(color: muted))),
          )
        else
          SizedBox(
            height: 370,
            child: filteredCards.length == 1
                ? Center(
                    child: _cardTile(
                      filteredCards.single,
                      width: double.infinity,
                      styleSeed: filteredCards.single.styleSeed,
                      onTap: () => _cardDetails(filteredCards.single,
                          cards.indexOf(filteredCards.single)),
                    ),
                  )
                : PageView.builder(
                    controller: _walletPageController,
                    itemCount: filteredCards.length,
                    physics: const BouncingScrollPhysics(),
                    clipBehavior: Clip.none,
                    itemBuilder: (context, index) {
                      final card = filteredCards[index];
                      final originalIndex = cards.indexOf(card);
                      return AnimatedBuilder(
                        animation: _walletPageController,
                        builder: (context, child) {
                          final page = _walletPageController.hasClients
                              ? (_walletPageController.page ?? 0)
                              : 0.0;
                          final offset = (page - index).clamp(-1.0, 1.0);
                          final distance = offset.abs();
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, .0014)
                              ..rotateY(-offset * .48),
                            child: Transform.translate(
                              offset: Offset(0, distance * 10),
                              child: Transform.scale(
                                scale: 1 - distance * .14,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: LayoutBuilder(
                          builder: (context, constraints) => Center(
                            child: Hero(
                              tag:
                                  'wallet-card-${card.databaseId ?? identityHashCode(card)}',
                              child: _cardTile(
                                card,
                                width: constraints.maxWidth,
                                styleSeed: card.styleSeed,
                                onTap: () => _cardDetails(card, originalIndex),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        if (filteredCards.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(
              child: Text(
                'Swipe a card to view the next one',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _compare() => ComparePage(cards: cards);
  Widget _assistant() => AiChatPage(cards: cards);
  Widget _quickAction(
    List<List<dynamic>> icon,
    String label,
    VoidCallback onTap, {
    bool filled = false,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 86,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: filled
                        ? LinearGradient(colors: [brandAccent, brandAccentDeep])
                        : null,
                    color: filled ? null : softSurface,
                    boxShadow: [
                      BoxShadow(
                        color: filled
                            ? brandAccent.withValues(alpha: .24)
                            : panelShadow,
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: HugeIcon(
                    icon: icon,
                    size: 19,
                    color: filled
                        ? (isCardyDarkMode
                            ? const Color(0xFF171719)
                            : Colors.white)
                        : brandAccentDeep,
                  ),
                ),
                const SizedBox(height: 6),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: ink, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );

  Widget _panel({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: panelBorder),
          boxShadow: [
            BoxShadow(
              color: panelShadow,
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      );
  Widget _sectionTitle(String s, {String? action, VoidCallback? onTap}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            s,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          if (action != null)
            TextButton(
              onPressed: onTap,
              child: Text(action, style: TextStyle(color: accentColor)),
            ),
        ],
      );
  Widget _cardTile(
    CreditCard c, {
    required double width,
    required int styleSeed,
    VoidCallback? onTap,
  }) {
    final widthInsideLimit = width.isFinite && width < 300 ? width : 300.0;
    final digits = c.cardNumber.replaceAll(RegExp(r'\D'), '');
    final displayDigits = digits.length >= 12 ? digits : '';
    final visualStyle = _cardVisualStyle(styleSeed);
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: c.artworkPath != null && File(c.artworkPath!).existsSync()
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap,
                    child: _artworkCardFace(
                      width: 300,
                      bank: c.bank,
                      variant: c.name,
                      name: c.nickname.isEmpty ? c.name : c.nickname,
                      number: displayDigits,
                      expiry: c.expiryDate,
                      network: c.network,
                      path: c.artworkPath!,
                    ),
                  )
                : HorizontalCard(
                    width: 300,
                    cardNumber: displayDigits,
                    cardHolder: c.nickname.isEmpty ? c.name : c.nickname,
                    expiryDate: c.expiryDate.isEmpty ? 'MM/YY' : c.expiryDate,
                    cvv: '',
                    brand: _horizontalBrand(c.network),
                    cardTheme: visualStyle.theme,
                    isHolographic: visualStyle.isHolographic,
                    holoConfig: visualStyle.holoConfig,
                    thickness: 2,
                    isMasked: true,
                    enableCopy: false,
                    isDynamicCvv: false,
                    enableTilt: false,
                    onTap: onTap ?? () {},
                    bankLogo: c.bank.isEmpty
                        ? null
                        : Text(
                            c.bank.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: visualStyle.theme.textColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: widthInsideLimit,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${c.bank} · ${c.name} · ${c.network}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  c.active ? 'ACTIVE' : 'PAUSED',
                  style: TextStyle(
                    color: c.active ? const Color(0xFF7DE0A1) : muted,
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _artworkCardFace({
    required double width,
    required String bank,
    required String variant,
    required String name,
    required String number,
    required String expiry,
    required String network,
    required String path,
  }) {
    const textStyle = TextStyle(color: Colors.white, shadows: [
      Shadow(color: Colors.black87, blurRadius: 8),
    ]);
    final digits = number.replaceAll(RegExp(r'\D'), '');
    final masked = digits.length >= 4
        ? '••••  ••••  ••••  ${digits.substring(digits.length - 4)}'
        : '••••  ••••  ••••  ••••';
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: width,
        height: width * .63,
        child: Stack(fit: StackFit.expand, children: [
          Image.file(File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFF252936))),
          const DecoratedBox(
              decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x99000000), Color(0x22000000), Color(0xDD000000)],
              stops: [0, .46, 1],
            ),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bank.isEmpty ? 'CARD' : bank.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyle.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1)),
                        const SizedBox(height: 3),
                        Text(variant.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyle.copyWith(
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                                letterSpacing: .7)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _networkWordmark(network, textStyle),
                ]),
                const Spacer(),
                Text(masked,
                    style: textStyle.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Text(
                        name.isEmpty ? 'CARDHOLDER' : name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle.copyWith(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .8)),
                  ),
                  const SizedBox(width: 8),
                  Text('EXPIRES  ${expiry.isEmpty ? 'MM/YY' : expiry}',
                      style: textStyle.copyWith(
                          fontSize: 8, fontWeight: FontWeight.w700)),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _networkWordmark(String network, TextStyle textStyle) {
    final value = network.toLowerCase();
    Widget mark;
    if (value.contains('master')) {
      mark = SizedBox(
        width: 42,
        height: 24,
        child: Stack(children: [
          Positioned(
              left: 3,
              top: 2,
              child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                      color: Color(0xFFEB001B), shape: BoxShape.circle))),
          Positioned(
              left: 17,
              top: 2,
              child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                      color: Color(0xFFF79E1B), shape: BoxShape.circle))),
        ]),
      );
    } else if (value.contains('visa')) {
      mark = Text('VISA',
          style: textStyle.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              letterSpacing: -.7));
    } else if (value.contains('amex') || value.contains('american express')) {
      mark = Text('AMEX',
          style: textStyle.copyWith(
              fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: .5));
    } else if (value.contains('rupay')) {
      mark = Text('RuPay',
          style: textStyle.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic));
    } else if (value.contains('jcb')) {
      mark = Row(mainAxisSize: MainAxisSize.min, children: [
        _jcbMark(color: const Color(0xFF1683C4), label: 'J'),
        _jcbMark(color: const Color(0xFFCC2633), label: 'C'),
        _jcbMark(color: const Color(0xFF3A9B50), label: 'B'),
      ]);
    } else {
      mark = Text(network.toUpperCase(),
          style: textStyle.copyWith(
              fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .4));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: .24)),
      ),
      child: mark,
    );
  }

  Widget _jcbMark({required Color color, required String label}) => Container(
        width: 11,
        height: 17,
        alignment: Alignment.center,
        color: color,
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900)),
      );

  CardBrand _horizontalBrand(String network) {
    switch (network.toLowerCase()) {
      case 'visa':
        return CardBrand.visa;
      case 'mastercard':
      case 'master card':
        return CardBrand.mastercard;
      case 'amex':
      case 'american express':
        return CardBrand.americanExpress;
      case 'discover':
        return CardBrand.discover;
      default:
        return CardBrand.generic;
    }
  }

  ({
    HorizontalCardTheme theme,
    bool isHolographic,
    HoloFoilConfig? holoConfig,
  }) _cardVisualStyle(int seed) {
    final random = math.Random(seed < 0 ? 0 : seed);
    final colorThemes = <HorizontalCardTheme>[
      CardPresets.solidMatteBlack,
      CardPresets.solidCeramicWhite,
      CardPresets.solidCobaltBlue,
      CardPresets.solidHotCoral,
      CardPresets.solidNubankPurple,
      CardPresets.solidEmerald,
      CardPresets.crimsonOrbit,
      CardPresets.royalAmethyst,
      CardPresets.oceanAzure,
      CardPresets.midnightSapphire,
    ];
    final metalThemes = <HorizontalCardTheme>[
      CardPresets.solidMatteBlack,
      CardPresets.appleTitanium,
      CardPresets.platinumHologram,
      CardPresets.obsidianBlack,
    ];
    final base = colorThemes[random.nextInt(colorThemes.length)];
    final metal = metalThemes[random.nextInt(metalThemes.length)];
    final pattern = random.nextInt(4);
    final patternColor = base.textColor.withValues(alpha: .16);
    final painter = switch (pattern) {
      1 => HorizontalOrbitalRingsPainter(
          primaryColor: patternColor,
          accentColor: patternColor.withValues(alpha: .55),
        ),
      2 => HorizontalMeshGridPainter(
          gridColor: patternColor,
          spacing: 14 + random.nextInt(8).toDouble(),
        ),
      3 => HorizontalGuillochePainter(
          primaryColor: patternColor,
          accentColor: patternColor.withValues(alpha: .65),
        ),
      _ => null,
    };
    final effect = random.nextInt(HoloStyle.values.length + 1);
    final holoConfig = effect == 0
        ? null
        : HoloFoilConfig(
            style: HoloStyle.values[effect - 1],
            intensity: .14 + random.nextDouble() * .13,
          );
    return (
      theme: HorizontalCardTheme(
        backgroundGradient: base.backgroundGradient,
        backgroundColor: base.backgroundColor,
        textColor: base.textColor,
        labelColor: base.labelColor,
        textFinish: metal.textFinish,
        backgroundPainter: painter,
        borderRadius: base.borderRadius,
        border: metal.border ?? base.border,
        shadows: metal.shadows ?? base.shadows,
        glareColor: metal.glareColor,
        edgeColor: metal.edgeColor ?? base.edgeColor,
      ),
      isHolographic: holoConfig != null,
      holoConfig: holoConfig,
    );
  }

  String _networkFromNumber(String number) {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('4')) return 'Visa';
    final mastercardPrefix =
        digits.length >= 4 ? int.tryParse(digits.substring(0, 4)) : null;
    if (RegExp(r'^5[1-5]').hasMatch(digits) ||
        (mastercardPrefix != null &&
            mastercardPrefix >= 2221 &&
            mastercardPrefix <= 2720)) {
      return 'Mastercard';
    }
    if (RegExp(r'^(508[5-9]|607[0-8]|608[0-3]|6069[89]|6521[5-9])')
        .hasMatch(digits)) {
      return 'RuPay';
    }
    if (digits.startsWith('34') || digits.startsWith('37')) {
      return 'American Express';
    }
    if (digits.startsWith('36') ||
        RegExp(r'^3(?:0[0-5]|[89])').hasMatch(digits)) {
      return 'Diners Club International';
    }
    if (digits.startsWith('6011') || digits.startsWith('65')) {
      return 'Discover';
    }
    return 'Other';
  }

  int _panLength(String network) {
    switch (network) {
      case 'American Express':
        return 15;
      case 'Diners Club International':
        return 14;
      case 'Other':
        return 16;
      default:
        return 16;
    }
  }

  bool _hasValidPanLength(String network, int length) =>
      length == _panLength(network);

  int _cvvLength(String network) => network == 'American Express' ? 4 : 3;

  DateTime? _expiryMonthEnd(String value) {
    final match = RegExp(r'^(0[1-9]|1[0-2])/([0-9]{2})$').firstMatch(value);
    if (match == null) return null;
    final month = int.parse(match.group(1)!);
    final year = 2000 + int.parse(match.group(2)!);
    return DateTime(year, month + 1, 0, 23, 59, 59);
  }

  List<CreditCard> _cardsExpiringSoon() {
    final now = DateTime.now();
    final horizon = DateTime(now.year, now.month + 3, now.day);
    return cards.where((card) {
      final expiry = _expiryMonthEnd(card.expiryDate);
      return card.active &&
          expiry != null &&
          !expiry.isBefore(now) &&
          !expiry.isAfter(horizon);
    }).toList();
  }

  void _trimDigits(TextEditingController controller, int maxLength) {
    final digits = controller.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= maxLength) return;
    final trimmed = _groupCardNumber(digits.substring(0, maxLength));
    controller.value = TextEditingValue(
      text: trimmed,
      selection: TextSelection.collapsed(offset: trimmed.length),
    );
  }

  Widget _tiltedCard({required Widget child}) => Tilt(
        tiltConfig: const TiltConfig(
          angle: 8,
          moveDuration: Duration(milliseconds: 120),
          leaveDuration: Duration(milliseconds: 320),
          enableGestureSensors: false,
        ),
        child: TiltBaseContainer(
          borderRadius: BorderRadius.circular(15),
          lightConfig: const LightConfig(maxIntensity: .12),
          shadowConfig: const ShadowBaseConfig(maxIntensity: .14),
          child: child,
        ),
      );
  Widget _empty(
    String title,
    String text,
    List<List<dynamic>> icon, {
    String? button,
    VoidCallback? onTap,
  }) =>
      _panel(
        child: Column(
          children: [
            HugeIcon(icon: icon, size: 38, color: muted),
            const SizedBox(height: 13),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
            if (button != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onTap, child: Text(button)),
            ],
          ],
        ),
      );
  Future<void> _chooseAddCard() async {
    await _editCard();
  }

  Future<void> _scanCard() async {
    try {
      final scanned = await CardScanner.scanCard(
        scanOptions: CardScanOptions(
          scanCardHolderName: false,
        ),
      );
      if (!mounted || scanned == null) return;
      final number = scanned.cardNumber.replaceAll(RegExp(r'\D'), '');
      if (number.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not read the card number. Try again or enter it manually.')),
        );
        return;
      }
      final network = _networkFromNumber(number);
      await _editCard(
        scannedNumber: number,
        scannedExpiry: scanned.expiryDate,
        scannedNetwork: network,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Card scanning could not start. Check camera permission or enter the card manually.')),
      );
    }
  }

  Future<void> _browseCatalogue() async {
    final entry = await Navigator.of(context).push<CardCatalogEntry>(
      cardyPageRoute((_) => const CardCataloguePage()),
    );
    if (entry != null && mounted) await _editCard(catalogue: entry);
  }

  Future<void> _editCard(
      {CreditCard? existing,
      int? index,
      CardCatalogEntry? catalogue,
      String? scannedNumber,
      String? scannedExpiry,
      String? scannedNetwork}) async {
    final styleSeed = existing?.styleSeed ?? _newCardStyleSeed();
    final form = GlobalKey<FormState>();
    final catalogNotes = catalogue == null
        ? ''
        : [
            catalogue.summary,
            if (catalogue.details['Key Highlights']?.isNotEmpty == true)
              'Key highlights: ${catalogue.details['Key Highlights']}',
            'Reference: ${catalogue.detailUrl}',
          ].where((value) => value.trim().isNotEmpty).join('\n\n');
    final catalogNetwork = (catalogue?.details['Network'] ?? '').toLowerCase();
    final prefNetwork = catalogNetwork.contains('mastercard')
        ? 'Mastercard'
        : catalogNetwork.contains('diners')
            ? 'Diners Club International'
            : catalogNetwork.contains('rupay')
                ? 'RuPay'
                : (catalogNetwork.contains('amex') ||
                        catalogNetwork.contains('american express'))
                    ? 'American Express'
                    : catalogNetwork.contains('visa')
                        ? 'Visa'
                        : 'Other';
    final bank = TextEditingController(text: existing?.bank ?? catalogue?.bank),
        name = TextEditingController(text: existing?.name ?? catalogue?.name),
        cardNumber = TextEditingController(
          text: _groupCardNumber(existing?.cardNumber ?? scannedNumber ?? ''),
        ),
        expiry = TextEditingController(
            text: existing?.expiryDate ?? scannedExpiry ?? ''),
        cvv = TextEditingController(text: existing?.cvv ?? '');
    var network = existing?.network ??
        scannedNetwork ??
        (catalogue == null ? 'Other' : prefNetwork);
    var networkWasChosen =
        existing != null || (catalogue != null && prefNetwork != 'Other');
    bool revealNumber = false, revealCvv = false;
    String? artworkPath = existing?.artworkPath;
    String? pickedArtworkPath;
    Future<dynamic>? sheetTransitionCompleted;
    await Navigator.of(context).push<void>(
      cardyPageRoute<void>((ctx) {
        sheetTransitionCompleted = ModalRoute.of(ctx)?.completed;
        return Scaffold(
          appBar: AppBar(
            title: Text(existing == null ? 'Add a card' : 'Edit card'),
          ),
          body: SafeArea(
            child: StatefulBuilder(
              builder: (ctx, setSheet) => Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
                child: Form(
                  key: form,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sensitive details are kept on this device.',
                            style: TextStyle(color: muted)),
                        const SizedBox(height: 16),
                        _cardPreview(
                          bank: bank.text,
                          name: name.text,
                          nickname: existing?.nickname ?? '',
                          number: cardNumber.text,
                          expiry: expiry.text,
                          network: network,
                          styleSeed: styleSeed,
                          showBack: false,
                          cvv: cvv.text,
                          artworkPath: artworkPath,
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final image = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1600,
                                imageQuality: 92,
                              );
                              if (image == null) return;
                              setSheet(() {
                                artworkPath = image.path;
                                pickedArtworkPath = image.path;
                              });
                            },
                            icon: const HugeIcon(
                                icon: HugeIcons.strokeRoundedImage01),
                            label: Text(artworkPath == null
                                ? 'Choose card image'
                                : 'Change image'),
                          ),
                          if (artworkPath != null)
                            TextButton(
                              onPressed: () => setSheet(() {
                                artworkPath = null;
                                pickedArtworkPath = null;
                              }),
                              child: const Text('Use generated style'),
                            ),
                        ]),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                              'Card artwork is stored only on this device.',
                              style: TextStyle(color: muted, fontSize: 12)),
                        ),
                        const SizedBox(height: 20),
                        _field(bank, 'Bank or issuer'),
                        _field(name, 'Card name and variant'),
                        DropdownButtonFormField<String>(
                          value: network,
                          decoration:
                              const InputDecoration(labelText: 'Card network'),
                          items: const [
                            'Visa',
                            'Mastercard',
                            'RuPay',
                            'American Express',
                            'Diners Club International',
                            'Discover',
                            'JCB',
                            'Other',
                          ]
                              .map((value) => DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value),
                                  ))
                              .toList(),
                          onChanged: (value) => setSheet(() {
                            network = value ?? 'Other';
                            networkWasChosen = true;
                            _trimDigits(cardNumber, _panLength(network));
                            _trimDigits(cvv, _cvvLength(network));
                          }),
                        ),
                        const SizedBox(height: 12),
                        FormField<String>(
                          initialValue: cardNumber.text,
                          validator: (value) {
                            final digits =
                                value?.replaceAll(RegExp(r'\D'), '') ?? '';
                            if (digits.isEmpty && existing != null) {
                              return null;
                            }
                            if (existing != null &&
                                digits == existing.cardNumber) {
                              return null;
                            }
                            if (!_hasValidPanLength(network, digits.length)) {
                              return 'Enter ${_panLength(network)} digits';
                            }
                            return null;
                          },
                          builder: (fieldState) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CardNumberBoxes(
                                value: cardNumber.text,
                                maxLength: _panLength(network),
                                obscure: !revealNumber,
                                onChanged: (digits) {
                                  cardNumber.text = digits;
                                  fieldState.didChange(digits);
                                  if (!networkWasChosen) {
                                    final detected = _networkFromNumber(digits);
                                    if (detected != network) {
                                      network = detected;
                                      _trimDigits(cvv, _cvvLength(network));
                                    }
                                  }
                                  setSheet(() {});
                                },
                                onToggleVisibility: () => setSheet(
                                  () => revealNumber = !revealNumber,
                                ),
                              ),
                              if (fieldState.hasError)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 6,
                                    left: 12,
                                  ),
                                  child: Text(
                                    fieldState.errorText!,
                                    style: TextStyle(
                                      color: Theme.of(ctx).colorScheme.error,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(
                              child: _paymentField(
                            expiry,
                            'Expiry date',
                            hint: 'MM/YY',
                            required: existing == null ||
                                (existing.expiryDate.isNotEmpty),
                            formatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9/]'),
                              ),
                              LengthLimitingTextInputFormatter(5),
                            ],
                            onChanged: (value) {
                              final digits =
                                  value.replaceAll(RegExp(r'\D'), '');
                              final formatted = digits.length > 2
                                  ? '${digits.substring(0, 2)}/${digits.substring(2, digits.length.clamp(2, 4).toInt())}'
                                  : digits;
                              if (formatted != value) {
                                expiry.value = TextEditingValue(
                                    text: formatted,
                                    selection: TextSelection.collapsed(
                                        offset: formatted.length));
                              }
                              setSheet(() {});
                            },
                            validator: (value) {
                              if ((value ?? '').isEmpty && existing != null)
                                return null;
                              final match =
                                  RegExp(r'^(0[1-9]|1[0-2])/([0-9]{2})$')
                                      .firstMatch(value ?? '');
                              if (match == null) return 'Use MM/YY';
                              final month = int.parse(match.group(1)!);
                              final year = 2000 + int.parse(match.group(2)!);
                              final now = DateTime.now();
                              if (year < now.year ||
                                  (year == now.year && month < now.month))
                                return 'Card has expired';
                              return null;
                            },
                          )),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _paymentField(
                            cvv,
                            'CVV',
                            hint: '•••',
                            obscure: !revealCvv,
                            onToggle: () =>
                                setSheet(() => revealCvv = !revealCvv),
                            onChanged: (_) => setSheet(() {}),
                            validator: (value) => value != null &&
                                    value.isNotEmpty &&
                                    value.length != _cvvLength(network)
                                ? 'Enter ${_cvvLength(network)} digits'
                                : null,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(
                                  _cvvLength(network)),
                            ],
                          )),
                        ]),
                        Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                              'Card number and expiry are encrypted on this device. CVV stays in memory for this session and is never saved.',
                              style: TextStyle(color: muted, fontSize: 12)),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () async {
                              if (!form.currentState!.validate()) return;
                              // Form validation marks its inherited scope dirty to
                              // paint validation state. Let that frame finish before
                              // any save or route teardown begins.
                              await WidgetsBinding.instance.endOfFrame;
                              if (!ctx.mounted) return;
                              final digits =
                                  cardNumber.text.replaceAll(RegExp(r'\D'), '');
                              final card = CreditCard(
                                databaseId: existing?.databaseId,
                                styleSeed: styleSeed,
                                bank: bank.text.trim(),
                                name: name.text.trim(),
                                network: network,
                                nickname: existing?.nickname ?? '',
                                annualFee: existing?.annualFee ??
                                    catalogue?.annualFee ??
                                    0,
                                cashback: existing?.cashback ??
                                    catalogue?.cashbackRate ??
                                    0,
                                rewardRate: existing?.rewardRate ?? 0,
                                pointValue: existing?.pointValue ?? 0,
                                categories: existing?.categories ??
                                    catalogue?.category ??
                                    '',
                                notes: existing?.notes ?? catalogNotes,
                                cardNumber: digits,
                                expiryDate: expiry.text.trim(),
                                cvv: cvv.text.trim(),
                                secureDetails: existing?.secureDetails ?? '',
                                active: existing?.active ?? true,
                                rewardsStack: existing?.rewardsStack ?? false,
                                artworkPath: artworkPath,
                              );
                              String? copiedArtwork;
                              if (pickedArtworkPath != null) {
                                final directory = Directory(p.join(
                                    await getDatabasesPath(), 'card_art'));
                                await directory.create(recursive: true);
                                final extension = p
                                    .extension(pickedArtworkPath!)
                                    .toLowerCase();
                                final safeExtension = const {
                                  '.jpg',
                                  '.jpeg',
                                  '.png',
                                  '.webp'
                                }.contains(extension)
                                    ? extension
                                    : '.jpg';
                                copiedArtwork = p.join(directory.path,
                                    'art_${DateTime.now().microsecondsSinceEpoch}$safeExtension');
                                await File(pickedArtworkPath!)
                                    .copy(copiedArtwork);
                                card.artworkPath = copiedArtwork;
                              }
                              if (index == null) {
                                _resetWalletPage();
                                cards.add(card);
                              } else {
                                cards[index] = card;
                              }
                              FocusManager.instance.primaryFocus?.unfocus();
                              try {
                                await _persistCard(card, notify: false);
                              } catch (error) {
                                if (copiedArtwork != null) {
                                  try {
                                    await File(copiedArtwork).delete();
                                  } catch (_) {}
                                }
                                if (index == null) {
                                  cards.remove(card);
                                } else if (existing != null) {
                                  cards[index] = existing;
                                }
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Could not save card: $error')),
                                  );
                                }
                                return;
                              }
                              if (existing?.artworkPath != null &&
                                  existing!.artworkPath != card.artworkPath) {
                                try {
                                  await File(existing.artworkPath!).delete();
                                } catch (_) {}
                              }
                              if (!ctx.mounted) return;
                              await WidgetsBinding.instance.endOfFrame;
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor: isCardyDarkMode
                                  ? const Color(0xFF111111)
                                  : Colors.white,
                            ),
                            child: Text(
                              existing == null ? 'Save card' : 'Save changes',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
    final exitedSheet = sheetTransitionCompleted;
    if (exitedSheet != null) await exitedSheet;
    cvv.clear();
    for (final controller in [bank, name, cardNumber, expiry, cvv]) {
      controller.dispose();
    }
    if (mounted) setState(() {});
  }

  Widget _paymentField(
    TextEditingController controller,
    String label, {
    String? hint,
    bool required = false,
    bool obscure = false,
    VoidCallback? onToggle,
    ValueChanged<String>? onChanged,
    String? Function(String?)? validator,
    List<TextInputFormatter>? formatters,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: obscure,
          onChanged: onChanged,
          inputFormatters: formatters,
          validator: validator ??
              (value) => required && (value == null || value.isEmpty)
                  ? 'Required'
                  : null,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            suffixIcon: onToggle == null
                ? null
                : IconButton(
                    onPressed: onToggle,
                    icon: HugeIcon(
                        icon: obscure
                            ? HugeIcons.strokeRoundedEye
                            : HugeIcons.strokeRoundedEyeOff),
                  ),
          ),
        ),
      );

  Widget _cardPreview({
    required String bank,
    required String name,
    required String nickname,
    required String number,
    required String expiry,
    required String network,
    required int styleSeed,
    required bool showBack,
    required String cvv,
    String? artworkPath,
  }) {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    final displayDigits = digits.length >= 12 ? digits : '';
    final previewWidth =
        (MediaQuery.sizeOf(context).width - 40).clamp(280.0, 400.0).toDouble();
    if (showBack) {
      return _tiltedCard(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: previewWidth,
          height: 190,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFF232B42), Color(0xFF11141E), Color(0xFF3B261C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .12)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 14),
            Container(height: 38, color: Colors.black.withValues(alpha: .55)),
            const Spacer(),
            Row(children: [
              Expanded(
                  child: Container(
                      height: 34, color: Colors.white.withValues(alpha: .78))),
              const SizedBox(width: 10),
              Container(
                  width: 54,
                  height: 34,
                  alignment: Alignment.center,
                  color: Colors.white,
                  child: Text(cvv.isEmpty ? 'CVV' : '•••',
                      style:
                          TextStyle(color: ink, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 10),
            const Text('Stored securely on this device',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
        ),
      );
    }

    final visualStyle = _cardVisualStyle(styleSeed);
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: _tiltedCard(
          child: artworkPath != null && File(artworkPath).existsSync()
              ? _artworkCardFace(
                  width: previewWidth,
                  bank: bank,
                  variant: name,
                  name: (nickname.isNotEmpty ? nickname : name).isEmpty
                      ? 'YOUR NAME'
                      : (nickname.isNotEmpty ? nickname : name),
                  number: displayDigits,
                  expiry: expiry,
                  network: network,
                  path: artworkPath,
                )
              : HorizontalCard(
                  width: previewWidth,
                  cardNumber: displayDigits,
                  cardHolder: (nickname.isNotEmpty ? nickname : name).isEmpty
                      ? 'YOUR NAME'
                      : (nickname.isNotEmpty ? nickname : name),
                  expiryDate: expiry.isEmpty ? 'MM/YY' : expiry,
                  cvv: '',
                  brand: _horizontalBrand(network),
                  cardTheme: visualStyle.theme,
                  isHolographic: visualStyle.isHolographic,
                  holoConfig: visualStyle.holoConfig,
                  thickness: 2,
                  isMasked: true,
                  enableCopy: false,
                  isDynamicCvv: false,
                  enableTilt: false,
                  onTap: () {},
                  bankLogo: Text(
                    bank.isEmpty ? 'CARD' : bank.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: visualStyle.theme.textColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _detailItem(String label, String value, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(color: muted, fontSize: 11)),
                  const SizedBox(height: 3),
                  Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = true,
    bool numeric = false,
    int maxLines = 1,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: TextFormField(
          controller: c,
          maxLines: maxLines,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          validator: (v) =>
              required && (v == null || v.trim().isEmpty) ? 'Required' : null,
          decoration: InputDecoration(labelText: label),
        ),
      );
  void _cardDetails(CreditCard c, int i) {
    var revealNumber = false;
    var revealCvv = false;
    var showBack = false;
    final digits = c.cardNumber.replaceAll(RegExp(r'\D'), '');
    final lastFour =
        digits.length > 4 ? digits.substring(digits.length - 4) : digits;
    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      isScrollControlled: true,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 420),
        reverseDuration: Duration(milliseconds: 300),
      ),
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDetails) => SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    20 + MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Hero(
                        tag:
                            'wallet-card-${c.databaseId ?? identityHashCode(c)}',
                        child: _cardPreview(
                          bank: c.bank,
                          name: c.name,
                          nickname: c.nickname,
                          number: c.cardNumber,
                          expiry: c.expiryDate,
                          network: c.network,
                          styleSeed: c.styleSeed,
                          showBack: showBack,
                          cvv: c.cvv,
                          artworkPath: c.artworkPath,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () =>
                              setDetails(() => showBack = !showBack),
                          icon: HugeIcon(
                              icon: showBack
                                  ? HugeIcons.strokeRoundedCreditCard
                                  : HugeIcons.strokeRoundedFlipHorizontal),
                          label: Text(showBack ? 'Show front' : 'Show back'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            _detailItem('Bank / issuer', c.bank),
                            const Divider(height: 1),
                            _detailItem('Variant', c.name),
                            const Divider(height: 1),
                            _detailItem('Network', c.network),
                            const Divider(height: 1),
                            _detailItem(
                              'Card number',
                              digits.isEmpty
                                  ? 'Not entered'
                                  : revealNumber
                                      ? digits
                                          .replaceAllMapped(
                                            RegExp(r'.{4}'),
                                            (m) => '${m.group(0)} ',
                                          )
                                          .trim()
                                      : '•••• •••• •••• $lastFour',
                              trailing: digits.isEmpty
                                  ? null
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: revealNumber
                                              ? 'Hide card number'
                                              : 'Show card number',
                                          onPressed: () async {
                                            if (revealNumber) {
                                              setDetails(
                                                  () => revealNumber = false);
                                            } else if (await _authenticateSensitiveData() &&
                                                ctx.mounted) {
                                              setDetails(
                                                  () => revealNumber = true);
                                            }
                                          },
                                          icon: HugeIcon(
                                              icon: revealNumber
                                                  ? HugeIcons
                                                      .strokeRoundedEyeOff
                                                  : HugeIcons.strokeRoundedEye),
                                        ),
                                        IconButton(
                                          tooltip: 'Copy card number',
                                          onPressed: () async {
                                            if (await _authenticateSensitiveData()) {
                                              await _copyCardDetail(
                                                  digits, 'Card number');
                                            }
                                          },
                                          icon: const HugeIcon(
                                              icon:
                                                  HugeIcons.strokeRoundedCopy),
                                        ),
                                      ],
                                    ),
                            ),
                            const Divider(height: 1),
                            _detailItem(
                              'Expiry',
                              c.expiryDate.isEmpty
                                  ? 'Not entered'
                                  : c.expiryDate,
                              trailing: c.expiryDate.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Copy expiry date',
                                      onPressed: () => _copyCardDetail(
                                          c.expiryDate, 'Expiry date'),
                                      icon: const HugeIcon(
                                          icon: HugeIcons.strokeRoundedCopy),
                                    ),
                            ),
                            const Divider(height: 1),
                            _detailItem(
                              'CVV',
                              c.cvv.isEmpty
                                  ? 'Not entered'
                                  : revealCvv
                                      ? c.cvv
                                      : '•••',
                              trailing: c.cvv.isEmpty
                                  ? null
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: revealCvv
                                              ? 'Hide CVV'
                                              : 'Show CVV',
                                          onPressed: () async {
                                            if (revealCvv) {
                                              setDetails(
                                                  () => revealCvv = false);
                                            } else if (await _authenticateSensitiveData() &&
                                                ctx.mounted) {
                                              setDetails(
                                                  () => revealCvv = true);
                                            }
                                          },
                                          icon: HugeIcon(
                                              icon: revealCvv
                                                  ? HugeIcons
                                                      .strokeRoundedEyeOff
                                                  : HugeIcons.strokeRoundedEye),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _editCard(existing: c, index: i);
                            },
                            child: const Text('Edit'),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await _setActive(c, !c.active);
                            },
                            child: Text(c.active ? 'Deactivate' : 'Reactivate'),
                          ),
                          TextButton(
                            onPressed: () => _confirmDelete(c, ctx),
                            child: const Text(
                              'Delete',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )),
    );
  }

  Future<void> _copyCardDetail(String value, String label) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    _clipboardClearTimer?.cancel();
    _clipboardClearTimer = Timer(const Duration(seconds: 30), () async {
      try {
        final clip = await Clipboard.getData(Clipboard.kTextPlain);
        if (clip?.text == value) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } catch (_) {
        // Clipboard access can be denied while the app is backgrounded.
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied. Clipboard clears in 30 seconds.')),
    );
  }

  Future<bool> _authenticateSensitiveData() async {
    try {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Set a device screen lock to reveal card details.')),
          );
        }
        return false;
      }
      return await auth.authenticate(
        localizedReason: 'Authenticate to reveal sensitive card details',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not authenticate: $error')),
        );
      }
      return false;
    }
  }

  Future<void> _setActive(CreditCard card, bool active,
      {bool offerUndo = true}) async {
    final previous = card.active;
    final previousSecureDetails = card.secureDetails;
    _resetWalletPage();
    card.active = active;
    try {
      await _persistCard(card, notify: false);
      if (mounted) setState(() {});
      if (offerUndo && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(active ? 'Card reactivated.' : 'Card deactivated.'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => _setActive(card, previous, offerUndo: false),
            ),
          ),
        );
      }
    } catch (error) {
      card.active = previous;
      card.secureDetails = previousSecureDetails;
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update card: $error')),
        );
      }
    }
  }

  Future<bool> _confirmDelete(
      CreditCard card, BuildContext detailContext) async {
    final confirmed = await showDialog<bool>(
      context: detailContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this card?'),
        content:
            const Text('This removes the saved card details from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    final index = cards.indexOf(card);
    if (index < 0) return false;
    try {
      final db = await LocalDatabase.instance.database;
      if (card.databaseId != null) {
        await db.delete('cards', where: 'id = ?', whereArgs: [card.databaseId]);
      }
      _resetWalletPage();
      cards.removeAt(index);
      if (mounted) setState(() {});
      if (mounted && detailContext.mounted) Navigator.pop(detailContext);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Card deleted.'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => _undoDelete(card, index),
            ),
          ),
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete card: $error')),
        );
      }
      return false;
    }
  }

  Future<void> _undoDelete(CreditCard card, int index) async {
    _resetWalletPage();
    card.databaseId = null;
    cards.insert(index.clamp(0, cards.length).toInt(), card);
    try {
      await _persistCard(card, notify: false);
      if (mounted) setState(() {});
    } catch (error) {
      cards.remove(card);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not restore card: $error')),
        );
      }
    }
  }

  Future<void> _search() async {
    final selected = await showSearch<CreditCard?>(
      context: context,
      delegate: CardSearchDelegate(cards),
    );
    if (selected == null || !mounted) return;
    final index = cards.indexOf(selected);
    if (index < 0) return;
    setState(() => tab = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cardDetails(selected, index);
    });
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: surface,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 360),
        reverseDuration: Duration(milliseconds: 260),
      ),
      builder: (sheetContext) => SafeArea(
        child: ValueListenableBuilder<bool>(
          valueListenable: cardyDarkMode,
          builder: (context, darkMode, child) => SwitchListTile(
            title: const Text('Dark mode'),
            subtitle: const Text('Use a darker theme throughout Cardy.'),
            secondary: HugeIcon(
                icon: darkMode
                    ? HugeIcons.strokeRoundedMoon01
                    : HugeIcons.strokeRoundedSun01),
            value: darkMode,
            onChanged: (value) async {
              cardyDarkMode.value = value;
              final preferences = await SharedPreferences.getInstance();
              await preferences.setBool('dark_mode', value);
            },
          ),
        ),
      ),
    );
  }

  void _info(String title, String message) => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
}
