import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'package:silky_scroll/silky_scroll.dart';
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
import 'features/cards/card_catalogue_service.dart';
import 'features/cards/card_wallet_stack.dart';
import 'features/debit/debit_card.dart';
import 'features/identity/identity_document.dart';
import 'widgets/app_dropdown.dart';
import 'features/assistant/ai_chat_page.dart';
import 'features/security/app_lock.dart';
import 'features/settings/settings_page.dart';
import 'features/splash/splash_gate.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  biometricLockEnabled.value = preferences.getBool('biometric_lock') ?? true;
  cardyColorThemeIndex.value = (preferences.getInt('color_theme') ?? 0)
      .clamp(0, cardyColorThemes.length - 1);
  runApp(const CardyApp());
}

class CardyApp extends StatelessWidget {
  const CardyApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([cardyDarkMode, cardyColorThemeIndex]),
        builder: (context, child) => MaterialApp(
          title: 'Cardy',
          debugShowCheckedModeBanner: false,
          theme: cardyThemeData(Brightness.light),
          darkTheme: cardyThemeData(Brightness.dark),
          themeMode: cardyDarkMode.value ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => SplashGate(
            child: AppLockGate(child: child ?? const SizedBox.shrink()),
          ),
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
  int _walletResetKey = 0;
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
    super.dispose();
  }

  void _resetWalletPage() {
    if (!mounted) return;
    setState(() => _walletResetKey++);
  }

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      cardyDarkMode.value = preferences.getBool('dark_mode') ?? false;
      final database = await LocalDatabase.instance.database;
      var saved = (await database.query('cards', orderBy: 'id'))
          .map(CreditCard.fromDatabase)
          .toList();
      for (final card in saved) {
        if (card.secureDetails.isNotEmpty) {
          try {
            final details = await SecureCardData.decrypt(card.secureDetails);
            card.cardNumber = details['number']!;
            card.expiryDate = details['expiry']!;
            card.cvv = details['cvv']!;
          } catch (_) {
            // Keep the rest of the local card usable if secure data cannot be read.
          }
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
              card.cvv = details['cvv']!;
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
      final loadedDebit =
          (await database.query('debit_cards', orderBy: 'created_at'))
              .map(DebitCard.fromRow)
              .toList();
      for (final card in loadedDebit) {
        try {
          final details = await SecureCardData.decrypt(card.secureDetails);
          card.cardNumber = details['number']!;
          card.expiryDate = details['expiry']!;
          card.cvv = details['cvv']!;
        } catch (_) {
          // Keep the card listed even if its encrypted details cannot be read.
        }
      }
      final loadedIdentity =
          (await database.query('identity_documents', orderBy: 'created_at'))
              .map(IdentityDocument.fromRow)
              .toList();
      for (final document in loadedIdentity) {
        if (document.secureDetails.isEmpty) continue;
        try {
          document.idNumber =
              await SecureCardData.decryptText(document.secureDetails);
        } catch (_) {
          // Keep the document entry available if its encrypted number is unreadable.
        }
      }
      if (!mounted) return;
      setState(() {
        cards = saved;
        debitCards = loadedDebit;
        identityDocs = loadedIdentity;
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
    if (card.cardNumber.isNotEmpty ||
        card.expiryDate.isNotEmpty ||
        card.cvv.isNotEmpty) {
      card.secureDetails = await SecureCardData.encrypt(
        number: card.cardNumber,
        expiry: card.expiryDate,
        cvv: card.cvv,
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
      if (card.cardNumber.isNotEmpty ||
          card.expiryDate.isNotEmpty ||
          card.cvv.isNotEmpty) {
        card.secureDetails = await SecureCardData.encrypt(
          number: card.cardNumber,
          expiry: card.expiryDate,
          cvv: card.cvv,
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
    final titles = [
      '',
      'Credit Cards',
      'Debit Cards',
      'Identity',
      'AI Assistant',
    ];
    return Scaffold(
      appBar: tab == 0
          ? null
          : AppBar(
              title: Text(
                titles[tab],
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              actions: [
                if (tab != 2 && tab != 3)
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
              children: [
                _dashboard(),
                _myCards(),
                _debitTab(),
                _identityTab(),
                _assistant(),
              ],
            ),
      floatingActionButton: tab == 1 || tab == 2 || tab == 3
          ? FloatingActionButton.extended(
              onPressed: tab == 1
                  ? _chooseAddCard
                  : tab == 2
                      ? () => _editDebitCard()
                      : () => _editIdentity(),
              backgroundColor: accentColor,
              foregroundColor: onAccent,
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01),
              label: Text(tab == 1
                  ? 'Add card'
                  : tab == 2
                      ? 'Add debit card'
                      : 'Add document'),
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
                  title: const Text('Credit Cards'),
                ),
                SalomonBottomBarItem(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedWallet01),
                  title: const Text('Debit Cards'),
                ),
                SalomonBottomBarItem(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedIdCard),
                  title: const Text('Identity'),
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
    final favoriteCards =
        activeCards.where((entry) => entry.value.favorite).toList();
    final stackCards = (favoriteCards.isEmpty ? activeCards : favoriteCards)
        .take(5)
        .map((entry) => entry.value)
        .toList();
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning,'
        : hour < 18
            ? 'Good afternoon,'
            : 'Good evening,';
    return SafeArea(
      child: SilkyScroll(
          physics: const BouncingScrollPhysics(),
          edgeLockingDelay: Duration.zero,
          overScrollingLockingDelay: Duration.zero,
          builder: (_, scrollController, scrollPhysics) => ListView(
                controller: scrollController,
                physics: scrollPhysics,
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
                                    fontFamily: cardyDisplayFont,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Search cards',
                        onPressed: _search,
                        icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedSearch01),
                      ),
                      IconButton(
                        tooltip: 'Scan a card',
                        onPressed: _scanCard,
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedScan),
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: _openSettings,
                        icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedSettings01),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                          child: _quickAction(HugeIcons.strokeRoundedAdd01,
                              'Add card', _editCard,
                              filled: true)),
                      const SizedBox(width: 9),
                      Expanded(
                          child: _quickAction(HugeIcons.strokeRoundedGlobe,
                              'Browse', _browseCatalogue)),
                    ],
                  ),
                  if (_cardsExpiringSoon().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: warningSurface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedCalendarOff,
                            color: warningForeground,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_cardsExpiringSoon().map((card) => card.nickname.isEmpty ? card.name : card.nickname).join(', ')} expiring within 3 months',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 27),
                  _sectionTitle(
                      favoriteCards.isEmpty ? 'Your Cards' : 'Favorites',
                      action: 'See all',
                      onTap: () => setState(() => tab = 1)),
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
                    _homeCardStack(
                      count: stackCards.length,
                      cardBuilder: (i, width) => _cardTile(
                        stackCards[i],
                        width: width,
                        styleSeed: stackCards[i].styleSeed,
                        showCaption: false,
                        onTap: () => _cardDetails(
                            stackCards[i], cards.indexOf(stackCards[i])),
                      ),
                      caption: 'SAVED CARDS',
                      total: cards.length,
                      onOpen: () => setState(() => tab = 1),
                      backColor: stackBack,
                      pocketColor: bottomBarBackground,
                    ),
                ],
              )),
    );
  }

  Widget _homeCardStack({
    required int count,
    required Widget Function(int index, double width) cardBuilder,
    required String caption,
    required int total,
    required VoidCallback onOpen,
    required Color backColor,
    required Color pocketColor,
  }) =>
      RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const peek = 48.0;
            const inset = 14.0;
            const taper = 12.0;
            const pocketHeight = 118.0;
            final width = constraints.maxWidth;
            final cardWidth = width - inset * 2;
            final hump = width * .075;
            final bottomCardTop = inset + peek * (count - 1);
            final pocketTop = inset + peek * (count - 1) + cardWidth * .63 * .5;
            return SizedBox(
              width: width,
              height: pocketTop + pocketHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: bottomCardTop,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: backColor,
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                  for (var i = 0; i < count; i++)
                    Positioned(
                      top: inset + i * peek,
                      left: inset + (count - 1 - i) * taper,
                      right: inset + (count - 1 - i) * taper,
                      height: cardWidth * .63,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .32),
                              blurRadius: 16,
                              spreadRadius: -2,
                              offset: const Offset(0, -6),
                            ),
                          ],
                        ),
                        child: RepaintBoundary(
                          child: cardBuilder(
                            i,
                            width - (inset + (count - 1 - i) * taper) * 2,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: pocketTop - hump,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onOpen,
                      child: CustomPaint(
                        painter: _WalletPocketPainter(
                          hump: hump,
                          color: pocketColor,
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(22, hump + 20, 22, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                caption,
                                style: TextStyle(
                                  color: bottomBarUnselected,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    '$total',
                                    style: TextStyle(
                                      color: bottomBarSelected,
                                      fontSize: 30,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'View wallet',
                                    style: TextStyle(
                                      color: bottomBarUnselected,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

  List<IdentityDocument> identityDocs = [];
  final Map<String, Future<Uint8List>> _identityArtworkCache = {};

  Future<Uint8List> _identityArtworkBytes(String path) =>
      _identityArtworkCache.putIfAbsent(path, () async {
        final encrypted = await File(path).readAsString();
        final encoded = await SecureCardData.decryptText(encrypted);
        return base64Decode(encoded);
      });

  Widget _identityArtworkImage(String path, double width) =>
      FutureBuilder<Uint8List>(
        future: _identityArtworkBytes(path),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.memory(snapshot.data!,
                fit: BoxFit.cover,
                cacheWidth: (width * 3).round(),
                errorBuilder: (_, __, ___) => Container(color: softSurface));
          }
          return Container(color: softSurface);
        },
      );

  String _maskedIdentityNumber(String value) {
    final compact = value.replaceAll(RegExp(r'\s'), '');
    final visible =
        compact.length > 4 ? compact.substring(compact.length - 4) : compact;
    return compact.isEmpty ? '' : '•••• $visible';
  }

  Widget _identityFace(IdentityDocument doc, double width,
      {bool artworkIsTemporary = false}) {
    final idNumber = doc.idNumber.replaceAll(RegExp(r'\s'), '');
    final lastFour = idNumber.length > 4
        ? idNumber.substring(idNumber.length - 4)
        : idNumber;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: width,
        height: width * .63,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF1B1C1F),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(fit: StackFit.expand, children: [
          if (doc.artworkPath != null && File(doc.artworkPath!).existsSync())
            Positioned.fill(
              child: artworkIsTemporary
                  ? Image.file(
                      File(doc.artworkPath!),
                      fit: BoxFit.cover,
                      cacheWidth: (width * 3).round(),
                    )
                  : _identityArtworkImage(doc.artworkPath!, width),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: doc.artworkPath != null &&
                        File(doc.artworkPath!).existsSync()
                    ? [
                        Colors.black.withValues(alpha: .28),
                        Colors.black.withValues(alpha: .72),
                      ]
                    : [const Color(0xFF393A3F), const Color(0xFF171719)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(doc.type.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1)),
                  ),
                  const HugeIcon(
                    icon: HugeIcons.strokeRoundedIdCard,
                    color: Colors.white,
                  ),
                ]),
                const Spacer(),
                if (idNumber.isNotEmpty) ...[
                  Text('••••  ••••  $lastFour',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1)),
                  const SizedBox(height: 8),
                ],
                Text(
                  doc.holder.isEmpty ? 'HOLDER NAME' : doc.holder.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                  ),
                ),
                const SizedBox(height: 5),
                Text(doc.expiryLabel,
                    style: TextStyle(
                      color: doc.expired
                          ? const Color(0xFFFFB4B4)
                          : Colors.white.withValues(alpha: .8),
                      fontSize: 10,
                    )),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _persistIdentity(IdentityDocument doc) async {
    final database = await LocalDatabase.instance.database;
    doc.secureDetails = doc.idNumber.trim().isEmpty
        ? ''
        : await SecureCardData.encryptText(doc.idNumber.trim());
    if (doc.id == null) {
      doc.id = await database.insert('identity_documents', doc.toRow());
      identityDocs.add(doc);
    } else {
      await database.update(
        'identity_documents',
        doc.toRow(),
        where: 'id = ?',
        whereArgs: [doc.id],
      );
      final index = identityDocs.indexWhere((item) => item.id == doc.id);
      if (index >= 0) identityDocs[index] = doc;
    }
    if (mounted) setState(() {});
  }

  Future<void> _deleteIdentity(IdentityDocument doc) async {
    final database = await LocalDatabase.instance.database;
    await database.delete(
      'identity_documents',
      where: 'id = ?',
      whereArgs: [doc.id],
    );
    identityDocs.removeWhere((item) => item.id == doc.id);
    if (doc.artworkPath != null) {
      _identityArtworkCache.remove(doc.artworkPath);
      try {
        await File(doc.artworkPath!).delete();
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Widget _identityTab() => SilkyScroll(
      physics: const BouncingScrollPhysics(),
      edgeLockingDelay: Duration.zero,
      overScrollingLockingDelay: Duration.zero,
      builder: (_, scrollController, scrollPhysics) => ListView(
            controller: scrollController,
            physics: scrollPhysics,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
            children: [
              const Text(
                'Identity documents',
                style: TextStyle(
                    fontFamily: cardyDisplayFont,
                    fontSize: 24,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '${identityDocs.length} saved · ID numbers encrypted on this device',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 18),
              if (identityDocs.isEmpty)
                _empty(
                  'Your documents will live here',
                  'Track expiry dates for Aadhaar, PAN, driving licence and more.',
                  HugeIcons.strokeRoundedIdCard,
                  button: 'Add your first document',
                  onTap: () => _editIdentity(),
                )
              else if (identityDocs.length == 1)
                GestureDetector(
                  onTap: () => _identityDetails(identityDocs.single),
                  child: LayoutBuilder(
                    builder: (context, constraints) => _identityFace(
                        identityDocs.single, constraints.maxWidth),
                  ),
                )
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CardWalletStack<IdentityDocument>(
                      cards: identityDocs,
                      cardBuilder: (doc, width, front) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: front ? () => _identityDetails(doc) : null,
                        child: _identityFace(doc, width),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Center(
                        child: Text(
                          'Swipe up or down to browse documents',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ));

  void _identityDetails(IdentityDocument doc) {
    var revealIdNumber = false;
    final idNumber = doc.idNumber.trim();
    final compactIdNumber = idNumber.replaceAll(RegExp(r'\s'), '');
    final maskedIdNumber = compactIdNumber.isEmpty
        ? 'Not entered'
        : '•••• •••• ${compactIdNumber.length > 4 ? compactIdNumber.substring(compactIdNumber.length - 4) : compactIdNumber}';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: surface,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDetails) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: _identityFace(
                    doc,
                    (MediaQuery.sizeOf(ctx).width - 40).clamp(260.0, 360.0),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: softSurface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _detailItem('Document', doc.type),
                      const Divider(height: 1),
                      _detailItem(
                          'Holder', doc.holder.isEmpty ? '—' : doc.holder),
                      const Divider(height: 1),
                      _detailItem(
                        'ID number',
                        revealIdNumber ? idNumber : maskedIdNumber,
                        trailing: idNumber.isEmpty
                            ? null
                            : Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  tooltip: revealIdNumber
                                      ? 'Hide ID number'
                                      : 'Reveal ID number',
                                  onPressed: () async {
                                    if (revealIdNumber) {
                                      revealIdNumber = false;
                                    } else if (await _authenticateSensitiveData()) {
                                      revealIdNumber = true;
                                    }
                                    if (ctx.mounted) setDetails(() {});
                                  },
                                  icon: HugeIcon(
                                    icon: revealIdNumber
                                        ? HugeIcons.strokeRoundedEyeOff
                                        : HugeIcons.strokeRoundedEye,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Copy ID number',
                                  onPressed: () async {
                                    if (await _authenticateSensitiveData()) {
                                      await _copyCardDetail(
                                          idNumber, 'ID number');
                                    }
                                  },
                                  icon: const HugeIcon(
                                      icon: HugeIcons.strokeRoundedCopy),
                                ),
                              ]),
                      ),
                      const Divider(height: 1),
                      _detailItem('Expiry', doc.expiryLabel),
                      const Divider(height: 1),
                      _detailItem('Note', doc.note.isEmpty ? '—' : doc.note),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _editIdentity(existing: doc);
                      },
                      child: const Text('Edit'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: ctx,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Delete this document?'),
                            content: const Text(
                                'This removes the saved entry from this device.'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('Delete',
                                    style: TextStyle(color: Colors.redAccent)),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _deleteIdentity(doc);
                      },
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
        ),
      ),
    );
  }

  Future<void> _editIdentity({IdentityDocument? existing}) async {
    var type = existing?.type ?? identityDocumentTypes.first;
    final holder = TextEditingController(text: existing?.holder),
        idNumber = TextEditingController(text: existing?.idNumber),
        expiry = TextEditingController(
            text: existing == null || existing.expiry.length < 7
                ? ''
                : '${existing.expiry.substring(5, 7)}/${existing.expiry.substring(0, 4)}'),
        note = TextEditingController(text: existing?.note);
    String? artworkPath = existing?.artworkPath;
    String? pickedArtworkPath;
    final formKey = GlobalKey<FormState>();
    Future<dynamic>? sheetTransitionCompleted;
    await Navigator.of(context).push<void>(
      cardyPageRoute<void>((ctx) {
        sheetTransitionCompleted = ModalRoute.of(ctx)?.completed;
        return Scaffold(
          appBar: AppBar(
            title: Text(existing == null ? 'Add a document' : 'Edit document'),
          ),
          body: SafeArea(
            child: StatefulBuilder(
              builder: (ctx, setSheet) => SilkyScroll(
                  physics: const BouncingScrollPhysics(),
                  edgeLockingDelay: Duration.zero,
                  overScrollingLockingDelay: Duration.zero,
                  builder: (_, scrollController, scrollPhysics) =>
                      SingleChildScrollView(
                        controller: scrollController,
                        physics: scrollPhysics,
                        padding: EdgeInsets.fromLTRB(
                          20,
                          8,
                          20,
                          20 + MediaQuery.of(ctx).viewInsets.bottom,
                        ),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _formRow(AppDropdown<String>(
                                initialItem: type,
                                labelText: 'Document',
                                items: identityDocumentTypes,
                                onChanged: (value) =>
                                    setSheet(() => type = value ?? type),
                              )),
                              _formRow(TextFormField(
                                controller: holder,
                                decoration:
                                    _sheetFieldDecoration('Holder name'),
                                onChanged: (_) => setSheet(() {}),
                              )),
                              _formRow(TextFormField(
                                controller: idNumber,
                                textCapitalization:
                                    TextCapitalization.characters,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(32)
                                ],
                                decoration: _sheetFieldDecoration('ID number'),
                                validator: (value) =>
                                    (value == null || value.trim().isEmpty)
                                        ? 'Enter the ID number'
                                        : null,
                                onChanged: (_) => setSheet(() {}),
                              )),
                              if (artworkPath != null &&
                                  File(artworkPath!).existsSync())
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Center(
                                    child: _identityFace(
                                      IdentityDocument(
                                        type: type,
                                        holder: holder.text,
                                        idNumber: idNumber.text,
                                        expiry: '',
                                        note: '',
                                        createdAt: DateTime.now(),
                                        artworkPath: artworkPath,
                                      ),
                                      (MediaQuery.sizeOf(ctx).width - 40)
                                          .clamp(260.0, 360.0),
                                      artworkIsTemporary:
                                          pickedArtworkPath != null,
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () async {
                                        final image =
                                            await ImagePicker().pickImage(
                                          source: ImageSource.gallery,
                                          maxWidth: 1000,
                                          maxHeight: 1000,
                                          imageQuality: 78,
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
                                          ? 'Add document artwork'
                                          : 'Change artwork'),
                                    ),
                                    if (artworkPath != null)
                                      TextButton(
                                        onPressed: () => setSheet(() {
                                          artworkPath = null;
                                          pickedArtworkPath = null;
                                        }),
                                        child: const Text('Remove'),
                                      ),
                                  ],
                                ),
                              ),
                              _formRow(TextFormField(
                                controller: expiry,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9/]')),
                                  LengthLimitingTextInputFormatter(7),
                                ],
                                onChanged: (value) {
                                  final digits =
                                      value.replaceAll(RegExp(r'\D'), '');
                                  final formatted = digits.length > 2
                                      ? '${digits.substring(0, 2)}/${digits.substring(2, digits.length.clamp(2, 6).toInt())}'
                                      : digits;
                                  if (formatted != value) {
                                    expiry.value = TextEditingValue(
                                        text: formatted,
                                        selection: TextSelection.collapsed(
                                            offset: formatted.length));
                                  }
                                },
                                validator: (value) {
                                  final text = value ?? '';
                                  if (text.isEmpty) return null;
                                  return RegExp(r'^(0[1-9]|1[0-2])/\d{4}$')
                                          .hasMatch(text)
                                      ? null
                                      : 'Use MM/YYYY or leave blank';
                                },
                                decoration: _sheetFieldDecoration(
                                    'Expiry (MM/YYYY)',
                                    hint: 'Leave blank if none'),
                              )),
                              _formRow(TextFormField(
                                controller: note,
                                maxLines: 3,
                                decoration: _sheetFieldDecoration('Note',
                                    hint: 'Optional reminder'),
                                validator: (value) => RegExp(r'\d{4,}')
                                        .hasMatch(value ?? '')
                                    ? 'Keep ID numbers in the ID number field'
                                    : null,
                              )),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  'ID numbers and artwork are encrypted on this device.',
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                              ),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: () async {
                                    if (!(formKey.currentState?.validate() ??
                                        false)) {
                                      return;
                                    }
                                    final parts = expiry.text.split('/');
                                    final document = IdentityDocument(
                                      id: existing?.id,
                                      type: type,
                                      holder: holder.text.trim(),
                                      expiry: parts.length == 2
                                          ? '${parts[1]}-${parts[0]}'
                                          : '',
                                      note: note.text.trim(),
                                      idNumber: idNumber.text.trim(),
                                      artworkPath: artworkPath,
                                      createdAt:
                                          existing?.createdAt ?? DateTime.now(),
                                    );
                                    String? copiedArtwork;
                                    try {
                                      if (pickedArtworkPath != null) {
                                        final directory = Directory(p.join(
                                            await getDatabasesPath(),
                                            'identity_art'));
                                        await directory.create(recursive: true);
                                        copiedArtwork = p.join(directory.path,
                                            'id_${DateTime.now().microsecondsSinceEpoch}.enc');
                                        final artworkBytes =
                                            await File(pickedArtworkPath!)
                                                .readAsBytes();
                                        final encryptedArtwork =
                                            await SecureCardData.encryptText(
                                                base64Encode(artworkBytes));
                                        await File(copiedArtwork)
                                            .writeAsString(encryptedArtwork);
                                        document.artworkPath = copiedArtwork;
                                      }
                                      await _persistIdentity(document);
                                    } catch (error) {
                                      if (copiedArtwork != null) {
                                        _identityArtworkCache
                                            .remove(copiedArtwork);
                                        try {
                                          await File(copiedArtwork).delete();
                                        } catch (_) {}
                                      }
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  'Could not save document: $error')),
                                        );
                                      }
                                      return;
                                    }
                                    if (existing?.artworkPath != null &&
                                        existing!.artworkPath !=
                                            document.artworkPath) {
                                      _identityArtworkCache
                                          .remove(existing.artworkPath);
                                      try {
                                        await File(existing.artworkPath!)
                                            .delete();
                                      } catch (_) {}
                                    }
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accentColor,
                                    foregroundColor: onAccent,
                                  ),
                                  child: Text(existing == null
                                      ? 'Save document'
                                      : 'Save changes'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )),
            ),
          ),
        );
      }),
    );
    final exitedPage = sheetTransitionCompleted;
    if (exitedPage != null) await exitedPage;
    for (final controller in [holder, idNumber, expiry, note]) {
      controller.dispose();
    }
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
    return SilkyScroll(
        physics: const BouncingScrollPhysics(),
        edgeLockingDelay: Duration.zero,
        overScrollingLockingDelay: Duration.zero,
        builder: (_, scrollController, scrollPhysics) => ListView(
              controller: scrollController,
              physics: scrollPhysics,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
              children: [
                const Text(
                  'Your wallet',
                  style: TextStyle(
                      fontFamily: cardyDisplayFont,
                      fontSize: 24,
                      fontWeight: FontWeight.w700),
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
                      SizedBox(
                        width: 160,
                        child: AppDropdown<String>(
                          initialItem: _bankFilter ?? 'All banks',
                          labelText: 'Bank',
                          items: ['All banks', ...banks],
                          onChanged: (value) {
                            _resetWalletPage();
                            setState(() => _bankFilter =
                                value == 'All banks' ? null : value);
                          },
                        ),
                      ),
                    if (networks.isNotEmpty)
                      SizedBox(
                        width: 160,
                        child: AppDropdown<String>(
                          initialItem: _networkFilter ?? 'All networks',
                          labelText: 'Network',
                          items: ['All networks', ...networks],
                          onChanged: (value) {
                            _resetWalletPage();
                            setState(() => _networkFilter =
                                value == 'All networks' ? null : value);
                          },
                        ),
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
                else if (filteredCards.length == 1)
                  SizedBox(
                    height: 370,
                    child: Center(
                      child: _cardTile(
                        filteredCards.single,
                        width: double.infinity,
                        styleSeed: filteredCards.single.styleSeed,
                        onTap: () => _cardDetails(filteredCards.single,
                            cards.indexOf(filteredCards.single)),
                      ),
                    ),
                  )
                else
                  CardWalletStack(
                    key: ValueKey(_walletResetKey),
                    cards: filteredCards,
                    cardBuilder: (card, width, front) => Hero(
                      tag:
                          'wallet-card-${card.databaseId ?? identityHashCode(card)}',
                      child: _cardTile(
                        card,
                        width: width,
                        styleSeed: card.styleSeed,
                        showCaption: false,
                        onTap: front
                            ? () => _cardDetails(card, cards.indexOf(card))
                            : null,
                      ),
                    ),
                  ),
                if (filteredCards.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Center(
                      child: Text(
                        'Swipe up or down to browse cards',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ));
  }

  List<DebitCard> debitCards = [];

  static const _debitNetworks = [
    'Visa',
    'Mastercard',
    'RuPay',
    'American Express',
    'Diners Club International',
    'Discover',
    'JCB',
    'Other',
  ];

  String _debitNetwork(DebitCard card) =>
      card.network.isEmpty ? _networkFromNumber(card.cardNumber) : card.network;

  CreditCard _debitPreview(DebitCard card) => CreditCard(
        bank: card.bank,
        name: card.label,
        nickname: card.holder,
        network: _debitNetwork(card),
        cardNumber: card.cardNumber,
        expiryDate: card.expiryDate,
        cvv: card.cvv,
        styleSeed: card.styleSeed,
        artworkPath: card.artworkPath,
      );

  Future<void> _persistDebit(DebitCard card) async {
    final database = await LocalDatabase.instance.database;
    card.secureDetails = await SecureCardData.encrypt(
      number: card.cardNumber,
      expiry: card.expiryDate,
      cvv: card.cvv,
    );
    if (card.id == null) {
      card.id = await database.insert('debit_cards', card.toRow());
      debitCards.add(card);
    } else {
      await database.update(
        'debit_cards',
        card.toRow(),
        where: 'id = ?',
        whereArgs: [card.id],
      );
      final index = debitCards.indexWhere((item) => item.id == card.id);
      if (index >= 0) debitCards[index] = card;
    }
    if (mounted) setState(() {});
  }

  Future<void> _deleteDebit(DebitCard card) async {
    final database = await LocalDatabase.instance.database;
    await database.delete('debit_cards', where: 'id = ?', whereArgs: [card.id]);
    debitCards.removeWhere((item) => item.id == card.id);
    if (mounted) setState(() {});
  }

  Widget _debitTab() => SilkyScroll(
      physics: const BouncingScrollPhysics(),
      edgeLockingDelay: Duration.zero,
      overScrollingLockingDelay: Duration.zero,
      builder: (_, scrollController, scrollPhysics) => ListView(
            controller: scrollController,
            physics: scrollPhysics,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
            children: [
              const Text(
                'Your debit cards',
                style: TextStyle(
                    fontFamily: cardyDisplayFont,
                    fontSize: 24,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '${debitCards.length} saved ${debitCards.length == 1 ? 'card' : 'cards'} · Encrypted on this device',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 18),
              if (debitCards.isEmpty)
                _empty(
                  'Your debit cards will live here',
                  'Save debit card details securely on this device.',
                  HugeIcons.strokeRoundedWallet01,
                  button: 'Add your first debit card',
                  onTap: () => _editDebitCard(),
                )
              else if (debitCards.length == 1)
                SizedBox(
                  height: 370,
                  child: Center(
                    child: _cardTile(
                      _debitPreview(debitCards.single),
                      width: double.infinity,
                      styleSeed: debitCards.single.styleSeed,
                      onTap: () => _debitDetails(debitCards.single),
                    ),
                  ),
                )
              else
                CardWalletStack<DebitCard>(
                  cards: debitCards,
                  cardBuilder: (card, width, front) => _cardTile(
                    _debitPreview(card),
                    width: width,
                    styleSeed: card.styleSeed,
                    showCaption: false,
                    onTap: front ? () => _debitDetails(card) : null,
                  ),
                ),
              if (debitCards.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Center(
                    child: Text(
                      'Swipe up or down to browse cards',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ));

  void _debitDetails(DebitCard card) {
    var revealed = false;
    final last4 = card.cardNumber.length >= 4
        ? card.cardNumber.substring(card.cardNumber.length - 4)
        : '••••';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: surface,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDetails) => SafeArea(
          child: SilkyScroll(
              physics: const BouncingScrollPhysics(),
              edgeLockingDelay: Duration.zero,
              overScrollingLockingDelay: Duration.zero,
              builder: (_, scrollController, scrollPhysics) =>
                  SingleChildScrollView(
                    controller: scrollController,
                    physics: scrollPhysics,
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
                        _cardPreview(
                          bank: card.bank,
                          name: card.label,
                          nickname: card.holder,
                          number: card.cardNumber,
                          expiry: card.expiryDate,
                          network: _debitNetwork(card),
                          styleSeed: card.styleSeed,
                          showBack: false,
                          cvv: card.cvv,
                          artworkPath: card.artworkPath,
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
                              _detailItem('Bank / issuer', card.bank),
                              const Divider(height: 1),
                              _detailItem('Label',
                                  card.label.isEmpty ? '—' : card.label),
                              const Divider(height: 1),
                              _detailItem(
                                'Card holder',
                                card.holder.isEmpty ? '—' : card.holder,
                              ),
                              const Divider(height: 1),
                              _detailItem(
                                'Card number',
                                revealed
                                    ? _spacedDigits(card.cardNumber)
                                    : '•••• •••• •••• $last4',
                              ),
                              const Divider(height: 1),
                              _detailItem(
                                'Expiry',
                                revealed && card.expiryDate.isNotEmpty
                                    ? card.expiryDate
                                    : '••/••',
                              ),
                              const Divider(height: 1),
                              _detailItem(
                                'CVV',
                                revealed && card.cvv.isNotEmpty
                                    ? card.cvv
                                    : '•••',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            if (!revealed &&
                                !await _authenticateSensitiveData()) {
                              return;
                            }
                            setDetails(() => revealed = !revealed);
                          },
                          icon: HugeIcon(
                              icon: revealed
                                  ? HugeIcons.strokeRoundedEyeOff
                                  : HugeIcons.strokeRoundedEye),
                          label: Text(
                              revealed ? 'Hide details' : 'Reveal details'),
                        ),
                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _editDebitCard(existing: card);
                              },
                              child: const Text('Edit'),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: ctx,
                                  builder: (dialogContext) => AlertDialog(
                                    title:
                                        const Text('Delete this debit card?'),
                                    content: const Text(
                                        'This removes the saved details from this device.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, true),
                                        child: const Text('Delete',
                                            style: TextStyle(
                                                color: Colors.redAccent)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                                if (ctx.mounted) Navigator.pop(ctx);
                                await _deleteDebit(card);
                              },
                              child: const Text(
                                'Delete',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )),
        ),
      ),
    );
  }

  String _spacedDigits(String digits) => digits
      .replaceAllMapped(RegExp(r'.{1,4}'), (match) => '${match.group(0)} ')
      .trim();

  Future<void> _editDebitCard({DebitCard? existing}) async {
    final bank = TextEditingController(text: existing?.bank),
        label = TextEditingController(text: existing?.label),
        holder = TextEditingController(text: existing?.holder),
        cardNumber = TextEditingController(text: existing?.cardNumber ?? ''),
        expiry = TextEditingController(text: existing?.expiryDate ?? ''),
        cvv = TextEditingController(text: existing?.cvv ?? '');
    final formKey = GlobalKey<FormState>();
    var revealNumber = false;
    var revealCvv = false;
    var networkChoice = existing?.network ?? '';
    var artworkPath = existing?.artworkPath;
    String? pickedArtworkPath;
    Future<dynamic>? sheetTransitionCompleted;
    await Navigator.of(context).push<void>(
      cardyPageRoute<void>((ctx) {
        sheetTransitionCompleted = ModalRoute.of(ctx)?.completed;
        return Scaffold(
          appBar: AppBar(
            title:
                Text(existing == null ? 'Add a debit card' : 'Edit debit card'),
          ),
          body: SafeArea(
            child: StatefulBuilder(
              builder: (ctx, setSheet) {
                final network = networkChoice.isEmpty
                    ? _networkFromNumber(cardNumber.text)
                    : networkChoice;
                return SilkyScroll(
                    physics: const BouncingScrollPhysics(),
                    edgeLockingDelay: Duration.zero,
                    overScrollingLockingDelay: Duration.zero,
                    builder: (_, scrollController, scrollPhysics) =>
                        SingleChildScrollView(
                          controller: scrollController,
                          physics: scrollPhysics,
                          padding: EdgeInsets.fromLTRB(
                            20,
                            8,
                            20,
                            20 + MediaQuery.of(ctx).viewInsets.bottom,
                          ),
                          child: Form(
                            key: formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _cardPreview(
                                  bank: bank.text,
                                  name: label.text,
                                  nickname: holder.text,
                                  number: cardNumber.text,
                                  expiry: expiry.text,
                                  network: network,
                                  styleSeed: existing?.styleSeed ??
                                      DateTime.now().millisecondsSinceEpoch ~/
                                          1000,
                                  showBack: false,
                                  cvv: cvv.text,
                                  artworkPath: artworkPath,
                                ),
                                const SizedBox(height: 16),
                                _formRow(TextFormField(
                                  controller: bank,
                                  onChanged: (_) => setSheet(() {}),
                                  validator: (value) =>
                                      (value == null || value.trim().isEmpty)
                                          ? 'Required'
                                          : null,
                                  decoration:
                                      _sheetFieldDecoration('Bank or issuer'),
                                )),
                                _formRow(TextFormField(
                                  controller: label,
                                  onChanged: (_) => setSheet(() {}),
                                  decoration: _sheetFieldDecoration('Label',
                                      hint: 'e.g. Salary account'),
                                )),
                                _formRow(TextFormField(
                                  controller: holder,
                                  onChanged: (_) => setSheet(() {}),
                                  decoration:
                                      _sheetFieldDecoration('Card holder name'),
                                )),
                                _formRow(AppDropdown<String>(
                                  key: ValueKey(network),
                                  initialItem: _debitNetworks.contains(network)
                                      ? network
                                      : 'Other',
                                  labelText: 'Card network',
                                  items: _debitNetworks,
                                  onChanged: (value) => setSheet(
                                    () => networkChoice = value ?? 'Other',
                                  ),
                                )),
                                Wrap(spacing: 8, children: [
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final image =
                                          await ImagePicker().pickImage(
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
                                const SizedBox(height: 14),
                                FormField<String>(
                                  initialValue: cardNumber.text,
                                  validator: (value) {
                                    final digits =
                                        value?.replaceAll(RegExp(r'\D'), '') ??
                                            '';
                                    return _hasValidPanLength(
                                            network, digits.length)
                                        ? null
                                        : 'Enter ${_panLength(network)} digits';
                                  },
                                  builder: (fieldState) => Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CardNumberBoxes(
                                          value: cardNumber.text,
                                          maxLength: _panLength(network),
                                          obscure: !revealNumber,
                                          onChanged: (digits) {
                                            cardNumber.text = digits;
                                            fieldState.didChange(digits);
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
                                                color: Theme.of(ctx)
                                                    .colorScheme
                                                    .error,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                Row(children: [
                                  Expanded(
                                    child: _paymentField(
                                      expiry,
                                      'Expiry date',
                                      hint: 'MM/YY',
                                      required: existing == null,
                                      formatters: [
                                        FilteringTextInputFormatter.allow(
                                            RegExp(r'[0-9/]')),
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
                                              selection:
                                                  TextSelection.collapsed(
                                                      offset:
                                                          formatted.length));
                                        }
                                        setSheet(() {});
                                      },
                                      validator: (value) {
                                        if ((value ?? '').isEmpty &&
                                            existing != null) {
                                          return null;
                                        }
                                        final match = RegExp(
                                                r'^(0[1-9]|1[0-2])/([0-9]{2})$')
                                            .firstMatch(value ?? '');
                                        return match == null
                                            ? 'Use MM/YY'
                                            : null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _paymentField(
                                      cvv,
                                      'CVV',
                                      hint: '•••',
                                      obscure: !revealCvv,
                                      onToggle: () => setSheet(
                                          () => revealCvv = !revealCvv),
                                      onChanged: (_) => setSheet(() {}),
                                      validator: (value) => value != null &&
                                              value.isNotEmpty &&
                                              value.length !=
                                                  _cvvLength(network)
                                          ? 'Enter ${_cvvLength(network)} digits'
                                          : null,
                                      formatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(
                                            _cvvLength(network)),
                                      ],
                                    ),
                                  ),
                                ]),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                      'Card number, expiry and CVV are encrypted on this device.',
                                      style: TextStyle(
                                          color: muted, fontSize: 12)),
                                ),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: () async {
                                      if (!(formKey.currentState?.validate() ??
                                          false)) {
                                        return;
                                      }
                                      final number = cardNumber.text.isEmpty
                                          ? existing?.cardNumber ?? ''
                                          : cardNumber.text;
                                      String? savedArtwork = artworkPath;
                                      if (pickedArtworkPath != null) {
                                        final directory = Directory(p.join(
                                            await getDatabasesPath(),
                                            'card_art'));
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
                                        savedArtwork = p.join(directory.path,
                                            'debit_art_${DateTime.now().microsecondsSinceEpoch}$safeExtension');
                                        await File(pickedArtworkPath!)
                                            .copy(savedArtwork);
                                      }
                                      final card = DebitCard(
                                        id: existing?.id,
                                        bank: bank.text.trim(),
                                        label: label.text.trim(),
                                        holder: holder.text.trim(),
                                        createdAt: existing?.createdAt ??
                                            DateTime.now(),
                                        network: networkChoice.isEmpty
                                            ? _networkFromNumber(number)
                                            : networkChoice,
                                        cardNumber: number,
                                        expiryDate: expiry.text.isEmpty
                                            ? existing?.expiryDate ?? ''
                                            : expiry.text,
                                        cvv: cvv.text.isEmpty
                                            ? existing?.cvv ?? ''
                                            : cvv.text,
                                        artworkPath: savedArtwork,
                                      );
                                      try {
                                        await _persistDebit(card);
                                        final oldArtwork =
                                            existing?.artworkPath;
                                        if (oldArtwork != null &&
                                            oldArtwork != savedArtwork) {
                                          try {
                                            await File(oldArtwork).delete();
                                          } catch (_) {}
                                        }
                                      } catch (error) {
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(ctx)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    'Could not save debit card: $error')),
                                          );
                                        }
                                        return;
                                      }
                                      if (ctx.mounted) Navigator.pop(ctx);
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: accentColor,
                                      foregroundColor: onAccent,
                                    ),
                                    child: Text(existing == null
                                        ? 'Save debit card'
                                        : 'Save changes'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ));
              },
            ),
          ),
        );
      }),
    );
    final exitedPage = sheetTransitionCompleted;
    if (exitedPage != null) await exitedPage;
    for (final controller in [bank, label, holder, cardNumber, expiry, cvv]) {
      controller.dispose();
    }
  }

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
                    color: filled ? onAccent : brandAccentDeep,
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
    bool showCaption = true,
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
          if (showCaption) ...[
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
                      color: c.active ? positiveColor : muted,
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
              cacheWidth: (width * 3).round(),
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFF252936))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
    String cardNotes(CardCatalogEntry? entry) => entry == null
        ? ''
        : [
            entry.summary,
            if (entry.details['Key Highlights']?.isNotEmpty == true)
              'Key highlights: ${entry.details['Key Highlights']}',
            'Reference: ${entry.detailUrl}',
          ].where((value) => value.trim().isNotEmpty).join('\n\n');
    const manualChoice = '__manual__';
    String? bankChoice, nameChoice;
    CardCatalogEntry? selectedEntry;
    final catalogCards = <CardCatalogEntry>[];
    void Function(void Function())? sheetRefresh;
    String networkFromCatalog(CardCatalogEntry? entry) {
      final raw = (entry?.details['Network'] ?? '').toLowerCase();
      return raw.contains('mastercard')
          ? 'Mastercard'
          : raw.contains('diners')
              ? 'Diners Club International'
              : raw.contains('rupay')
                  ? 'RuPay'
                  : (raw.contains('amex') || raw.contains('american express'))
                      ? 'American Express'
                      : raw.contains('visa')
                          ? 'Visa'
                          : 'Other';
    }

    final prefNetwork = networkFromCatalog(catalogue);
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
    () async {
      try {
        catalogCards.addAll(await CardCatalogueService.instance.list());
      } catch (_) {}
      final banks = catalogCards
          .map((entry) => entry.bank)
          .where((bank) => bank.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      final seedBank = bank.text.trim();
      if (seedBank.isNotEmpty) {
        bankChoice = banks.contains(seedBank) ? seedBank : manualChoice;
        if (bankChoice != manualChoice) {
          final names = catalogCards
              .where((entry) => entry.bank == bankChoice)
              .map((entry) => entry.name)
              .toSet()
              .toList()
            ..sort();
          final seedName = name.text.trim();
          nameChoice = names.contains(seedName) ? seedName : null;
          if (nameChoice != null) {
            selectedEntry = catalogCards.firstWhere(
              (entry) => entry.bank == bankChoice && entry.name == nameChoice,
            );
          }
        }
      }
      final refresh = sheetRefresh;
      if (refresh != null) refresh(() {});
    }();
    await Navigator.of(context).push<void>(
      cardyPageRoute<void>((ctx) {
        sheetTransitionCompleted = ModalRoute.of(ctx)?.completed;
        return Scaffold(
          appBar: AppBar(
            title: Text(existing == null ? 'Add a card' : 'Edit card'),
          ),
          body: SafeArea(
            child: StatefulBuilder(
              builder: (ctx, setSheet) {
                sheetRefresh = setSheet;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    18,
                    20,
                    MediaQuery.of(ctx).viewInsets.bottom + 20,
                  ),
                  child: Form(
                    key: form,
                    child: SilkyScroll(
                        physics: const BouncingScrollPhysics(),
                        edgeLockingDelay: Duration.zero,
                        overScrollingLockingDelay: Duration.zero,
                        builder: (_, scrollController, scrollPhysics) =>
                            SingleChildScrollView(
                              controller: scrollController,
                              physics: scrollPhysics,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'Sensitive details are kept on this device.',
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
                                        final image =
                                            await ImagePicker().pickImage(
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
                                        child:
                                            const Text('Use generated style'),
                                      ),
                                  ]),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(
                                        'Card artwork is stored only on this device.',
                                        style: TextStyle(
                                            color: muted, fontSize: 12)),
                                  ),
                                  const SizedBox(height: 20),
                                  Builder(
                                    builder: (_) {
                                      final banks = catalogCards
                                          .map((entry) => entry.bank)
                                          .where((bank) => bank.isNotEmpty)
                                          .toSet()
                                          .toList()
                                        ..sort();
                                      if (banks.isEmpty ||
                                          bankChoice == manualChoice) {
                                        return _field(bank, 'Bank or issuer');
                                      }
                                      return _formRow(AppDropdown<String>(
                                        initialItem: bankChoice,
                                        labelText: 'Bank or issuer',
                                        validator: (value) => value == null
                                            ? 'Select bank or pick manual entry'
                                            : null,
                                        items: [...banks, manualChoice],
                                        itemLabel: (value) =>
                                            value == manualChoice
                                                ? 'Other / enter manually'
                                                : value,
                                        onChanged: (value) => setSheet(() {
                                          if (value == manualChoice) {
                                            bankChoice = manualChoice;
                                            nameChoice = manualChoice;
                                            selectedEntry = null;
                                            return;
                                          }
                                          bankChoice = value;
                                          bank.text = value ?? '';
                                          final names = catalogCards
                                              .where((entry) =>
                                                  entry.bank == value)
                                              .map((entry) => entry.name)
                                              .where((n) => n.isNotEmpty)
                                              .toSet()
                                              .toList()
                                            ..sort();
                                          final seedName = name.text.trim();
                                          if (!names.contains(seedName)) {
                                            name.text = '';
                                            nameChoice = null;
                                            selectedEntry = null;
                                          } else {
                                            selectedEntry =
                                                catalogCards.firstWhere(
                                              (entry) =>
                                                  entry.bank == value &&
                                                  entry.name == seedName,
                                            );
                                          }
                                        }),
                                      ));
                                    },
                                  ),
                                  Builder(
                                    builder: (_) {
                                      final names = catalogCards
                                          .where((entry) =>
                                              entry.bank == bankChoice)
                                          .map((entry) => entry.name)
                                          .where((n) => n.isNotEmpty)
                                          .toSet()
                                          .toList()
                                        ..sort();
                                      if (catalogCards.isEmpty ||
                                          bankChoice == manualChoice ||
                                          nameChoice == manualChoice) {
                                        return _field(
                                            name, 'Card name and variant');
                                      }
                                      return _formRow(AppDropdown<String>(
                                        key: ValueKey(bankChoice),
                                        initialItem: names.contains(nameChoice)
                                            ? nameChoice
                                            : null,
                                        labelText: 'Card name and variant',
                                        hintText: bankChoice == null
                                            ? 'Pick a bank first'
                                            : 'Select the card variant',
                                        validator: (value) => value == null
                                            ? 'Select a variant or pick manual entry'
                                            : null,
                                        items: [...names, manualChoice],
                                        itemLabel: (value) =>
                                            value == manualChoice
                                                ? 'Other / enter manually'
                                                : value,
                                        onChanged: bankChoice == null
                                            ? null
                                            : (value) => setSheet(() {
                                                  if (value == manualChoice) {
                                                    nameChoice = manualChoice;
                                                    selectedEntry = null;
                                                    return;
                                                  }
                                                  nameChoice = value;
                                                  name.text = value ?? '';
                                                  selectedEntry =
                                                      catalogCards.firstWhere(
                                                    (entry) =>
                                                        entry.bank ==
                                                            bankChoice &&
                                                        entry.name == value,
                                                  );
                                                  if (!networkWasChosen &&
                                                      selectedEntry != null) {
                                                    final detected =
                                                        networkFromCatalog(
                                                            selectedEntry);
                                                    if (detected != 'Other') {
                                                      network = detected;
                                                      networkWasChosen = true;
                                                      _trimDigits(cardNumber,
                                                          _panLength(network));
                                                      _trimDigits(cvv,
                                                          _cvvLength(network));
                                                    }
                                                  }
                                                }),
                                      ));
                                    },
                                  ),
                                  _formRow(AppDropdown<String>(
                                    key: ValueKey(network),
                                    initialItem: network,
                                    labelText: 'Card network',
                                    items: const [
                                      'Visa',
                                      'Mastercard',
                                      'RuPay',
                                      'American Express',
                                      'Diners Club International',
                                      'Discover',
                                      'JCB',
                                      'Other',
                                    ],
                                    onChanged: (value) => setSheet(() {
                                      network = value ?? 'Other';
                                      networkWasChosen = true;
                                      _trimDigits(
                                          cardNumber, _panLength(network));
                                      _trimDigits(cvv, _cvvLength(network));
                                    }),
                                  )),
                                  const SizedBox(height: 12),
                                  FormField<String>(
                                    initialValue: cardNumber.text,
                                    validator: (value) {
                                      final digits = value?.replaceAll(
                                              RegExp(r'\D'), '') ??
                                          '';
                                      if (digits.isEmpty && existing != null) {
                                        return null;
                                      }
                                      if (existing != null &&
                                          digits == existing.cardNumber) {
                                        return null;
                                      }
                                      if (!_hasValidPanLength(
                                          network, digits.length)) {
                                        return 'Enter ${_panLength(network)} digits';
                                      }
                                      return null;
                                    },
                                    builder: (fieldState) => Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CardNumberBoxes(
                                          value: cardNumber.text,
                                          maxLength: _panLength(network),
                                          obscure: !revealNumber,
                                          onChanged: (digits) {
                                            cardNumber.text = digits;
                                            fieldState.didChange(digits);
                                            if (!networkWasChosen) {
                                              final detected =
                                                  _networkFromNumber(digits);
                                              if (detected != network) {
                                                network = detected;
                                                _trimDigits(
                                                    cvv, _cvvLength(network));
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
                                                color: Theme.of(ctx)
                                                    .colorScheme
                                                    .error,
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
                                              selection:
                                                  TextSelection.collapsed(
                                                      offset:
                                                          formatted.length));
                                        }
                                        setSheet(() {});
                                      },
                                      validator: (value) {
                                        if ((value ?? '').isEmpty &&
                                            existing != null) return null;
                                        final match = RegExp(
                                                r'^(0[1-9]|1[0-2])/([0-9]{2})$')
                                            .firstMatch(value ?? '');
                                        if (match == null) return 'Use MM/YY';
                                        final month =
                                            int.parse(match.group(1)!);
                                        final year =
                                            2000 + int.parse(match.group(2)!);
                                        final now = DateTime.now();
                                        if (year < now.year ||
                                            (year == now.year &&
                                                month < now.month))
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
                                      onToggle: () => setSheet(
                                          () => revealCvv = !revealCvv),
                                      onChanged: (_) => setSheet(() {}),
                                      validator: (value) => value != null &&
                                              value.isNotEmpty &&
                                              value.length !=
                                                  _cvvLength(network)
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
                                        'Card number, expiry and CVV are encrypted on this device.',
                                        style: TextStyle(
                                            color: muted, fontSize: 12)),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: () async {
                                        if (!form.currentState!.validate())
                                          return;
                                        // Form validation marks its inherited scope dirty to
                                        // paint validation state. Let that frame finish before
                                        // any save or route teardown begins.
                                        await WidgetsBinding
                                            .instance.endOfFrame;
                                        if (!ctx.mounted) return;
                                        final digits = cardNumber.text
                                            .replaceAll(RegExp(r'\D'), '');
                                        final entry =
                                            selectedEntry ?? catalogue;
                                        final card = CreditCard(
                                          databaseId: existing?.databaseId,
                                          styleSeed: styleSeed,
                                          bank: bank.text.trim(),
                                          name: name.text.trim(),
                                          network: network,
                                          nickname: existing?.nickname ?? '',
                                          annualFee: existing?.annualFee ??
                                              entry?.annualFee ??
                                              0,
                                          cashback: existing?.cashback ??
                                              entry?.cashbackRate ??
                                              0,
                                          rewardRate: existing?.rewardRate ?? 0,
                                          pointValue: existing?.pointValue ?? 0,
                                          categories: existing?.categories ??
                                              entry?.category ??
                                              '',
                                          notes: existing?.notes ??
                                              cardNotes(entry),
                                          cardNumber: digits,
                                          expiryDate: expiry.text.trim(),
                                          cvv: cvv.text.trim(),
                                          secureDetails:
                                              existing?.secureDetails ?? '',
                                          active: existing?.active ?? true,
                                          rewardsStack:
                                              existing?.rewardsStack ?? false,
                                          artworkPath: artworkPath,
                                        );
                                        String? copiedArtwork;
                                        if (pickedArtworkPath != null) {
                                          final directory = Directory(p.join(
                                              await getDatabasesPath(),
                                              'card_art'));
                                          await directory.create(
                                              recursive: true);
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
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                        try {
                                          await _persistCard(card,
                                              notify: false);
                                        } catch (error) {
                                          if (copiedArtwork != null) {
                                            try {
                                              await File(copiedArtwork)
                                                  .delete();
                                            } catch (_) {}
                                          }
                                          if (index == null) {
                                            cards.remove(card);
                                          } else if (existing != null) {
                                            cards[index] = existing;
                                          }
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(ctx)
                                                .showSnackBar(
                                              SnackBar(
                                                  content: Text(
                                                      'Could not save card: $error')),
                                            );
                                          }
                                          return;
                                        }
                                        if (existing?.artworkPath != null &&
                                            existing!.artworkPath !=
                                                card.artworkPath) {
                                          try {
                                            await File(existing.artworkPath!)
                                                .delete();
                                          } catch (_) {}
                                        }
                                        if (!ctx.mounted) return;
                                        await WidgetsBinding
                                            .instance.endOfFrame;
                                        if (ctx.mounted) Navigator.pop(ctx);
                                      },
                                      style: FilledButton.styleFrom(
                                        backgroundColor: accentColor,
                                        foregroundColor: onAccent,
                                      ),
                                      child: Text(
                                        existing == null
                                            ? 'Save card'
                                            : 'Save changes',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                  ),
                );
              },
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
    final hasArtwork = artworkPath != null && File(artworkPath).existsSync();
    final displayName = (nickname.isNotEmpty ? nickname : name).isEmpty
        ? 'YOUR NAME'
        : (nickname.isNotEmpty ? nickname : name);
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tiltedCard(
              child: hasArtwork
                  ? _artworkCardFace(
                      width: previewWidth,
                      bank: bank,
                      variant: name,
                      name: displayName,
                      number: displayDigits,
                      expiry: expiry,
                      network: network,
                      path: artworkPath,
                    )
                  : HorizontalCard(
                      width: previewWidth,
                      cardNumber: displayDigits,
                      cardHolder: displayName,
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
            if (hasArtwork) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: previewWidth,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${bank.isEmpty ? 'CARD' : bank.toUpperCase()}  ·  ${name.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _networkWordmark(
                        network, const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ],
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

  InputDecoration _sheetFieldDecoration(String label, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: muted, fontWeight: FontWeight.w500),
        floatingLabelStyle: TextStyle(color: ink, fontWeight: FontWeight.w600),
        filled: true,
        fillColor: softSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: brandAccent, width: 1.4),
        ),
      );

  Widget _formRow(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 14), child: child);

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = true,
    bool numeric = false,
    int maxLines = 1,
  }) =>
      _formRow(TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        validator: (v) =>
            required && (v == null || v.trim().isEmpty) ? 'Required' : null,
        decoration: _sheetFieldDecoration(label),
      ));
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
                child: SilkyScroll(
                    physics: const BouncingScrollPhysics(),
                    edgeLockingDelay: Duration.zero,
                    overScrollingLockingDelay: Duration.zero,
                    builder: (_, scrollController, scrollPhysics) =>
                        SingleChildScrollView(
                          controller: scrollController,
                          physics: scrollPhysics,
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
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: c.favorite
                                        ? 'Remove from favorites'
                                        : 'Add to favorites',
                                    onPressed: () async {
                                      await _setFavorite(c, !c.favorite);
                                      setDetails(() {});
                                    },
                                    icon: HugeIcon(
                                      icon: HugeIcons.strokeRoundedFavourite,
                                      color:
                                          c.favorite ? Colors.redAccent : muted,
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton.icon(
                                    onPressed: () =>
                                        setDetails(() => showBack = !showBack),
                                    icon: HugeIcon(
                                        icon: showBack
                                            ? HugeIcons.strokeRoundedCreditCard
                                            : HugeIcons
                                                .strokeRoundedFlipHorizontal),
                                    label: Text(
                                        showBack ? 'Show front' : 'Show back'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
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
                                                      setDetails(() =>
                                                          revealNumber = false);
                                                    } else if (await _authenticateSensitiveData() &&
                                                        ctx.mounted) {
                                                      setDetails(() =>
                                                          revealNumber = true);
                                                    }
                                                  },
                                                  icon: HugeIcon(
                                                      icon: revealNumber
                                                          ? HugeIcons
                                                              .strokeRoundedEyeOff
                                                          : HugeIcons
                                                              .strokeRoundedEye),
                                                ),
                                                IconButton(
                                                  tooltip: 'Copy card number',
                                                  onPressed: () async {
                                                    if (await _authenticateSensitiveData()) {
                                                      await _copyCardDetail(
                                                          digits,
                                                          'Card number');
                                                    }
                                                  },
                                                  icon: const HugeIcon(
                                                      icon: HugeIcons
                                                          .strokeRoundedCopy),
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
                                                  icon: HugeIcons
                                                      .strokeRoundedCopy),
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
                                                      setDetails(() =>
                                                          revealCvv = false);
                                                    } else if (await _authenticateSensitiveData() &&
                                                        ctx.mounted) {
                                                      setDetails(() =>
                                                          revealCvv = true);
                                                    }
                                                  },
                                                  icon: HugeIcon(
                                                      icon: revealCvv
                                                          ? HugeIcons
                                                              .strokeRoundedEyeOff
                                                          : HugeIcons
                                                              .strokeRoundedEye),
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
                                    child: Text(
                                        c.active ? 'Deactivate' : 'Reactivate'),
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
                        )),
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

  Future<void> _setFavorite(CreditCard card, bool favorite) async {
    final previous = card.favorite;
    card.favorite = favorite;
    if (mounted) setState(() {});
    try {
      final database = await LocalDatabase.instance.database;
      if (card.databaseId != null) {
        await database.update(
          'cards',
          {'is_favorite': favorite ? 1 : 0},
          where: 'id = ?',
          whereArgs: [card.databaseId],
        );
      }
    } catch (error) {
      card.favorite = previous;
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update favorite: $error')),
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
    Navigator.of(context).push<void>(
      cardyPageRoute<void>((_) => const SettingsPage()),
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

class _WalletPocketPainter extends CustomPainter {
  _WalletPocketPainter({required this.hump, required this.color});

  final double hump;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, hump + 26)
      ..quadraticBezierTo(0, hump, 26, hump)
      ..lineTo(w * .09, hump)
      ..cubicTo(w * .15, hump, w * .16, 0, w * .22, 0)
      ..lineTo(w * .78, 0)
      ..cubicTo(w * .84, 0, w * .85, hump, w * .91, hump)
      ..lineTo(w - 26, hump)
      ..quadraticBezierTo(w, hump, w, hump + 26)
      ..lineTo(w, h - 26)
      ..quadraticBezierTo(w, h, w - 26, h)
      ..lineTo(26, h)
      ..quadraticBezierTo(0, h, 0, h - 26)
      ..close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: .4), 8, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: .12),
    );
  }

  @override
  bool shouldRepaint(_WalletPocketPainter oldDelegate) =>
      oldDelegate.hump != hump || oldDelegate.color != color;
}
