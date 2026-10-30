import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'data/local_database.dart';
import 'data/secure_card_data.dart';
import 'features/cards/credit_card.dart';
import 'features/cards/card_catalogue.dart';
import 'features/cards/card_catalogue_page.dart';
import 'features/assistant/ai_chat_page.dart';

const ink = Color(0xFF121212);
const surface = Color(0xFF1C1C1E);
const orange = Color(0xFFFF7A00);
const muted = Color(0xFFA1A1AA);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CardWiseApp());
}

class CardWiseApp extends StatelessWidget {
  const CardWiseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'CardWise AI',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: ink,
          colorScheme: ColorScheme.fromSeed(
            seedColor: orange,
            brightness: Brightness.dark,
            surface: surface,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: ink,
            foregroundColor: Colors.white,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            hintStyle: const TextStyle(color: muted),
          ),
        ),
        home: const CardWiseHome(),
      );
}

class CardWiseHome extends StatefulWidget {
  const CardWiseHome({super.key});
  @override
  State<CardWiseHome> createState() => _CardWiseHomeState();
}

class _CardWiseHomeState extends State<CardWiseHome> {
  int tab = 0;
  bool loaded = false;
  List<CreditCard> cards = [];
  String query = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
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
        final preferences = await SharedPreferences.getInstance();
        final legacy = preferences.getString('cards');
        if (legacy != null) {
          saved = (jsonDecode(legacy) as List)
              .map((row) => CreditCard.fromJson(row as Map<String, dynamic>))
              .toList();
          await _replaceCardsInDatabase(database, saved);
          await preferences.remove('cards');
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
          'CardWise could not read its on-device database. Details: $error');
    }
  }

  Future<void> _save({bool notify = true}) async {
    final database = await LocalDatabase.instance.database;
    await _replaceCardsInDatabase(database, cards);
    if (notify && mounted) setState(() {});
  }

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
      }
      rows.add(card.toDatabase());
    }
    await database.transaction((txn) async {
      await txn.delete('cards');
      for (final row in rows) {
        await txn.insert('cards', row);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['CardWise AI', 'My Cards', 'AI Assistant'];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.credit_card, color: orange),
            const SizedBox(width: 9),
            Text(
              titles[tab],
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _search(),
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator(color: orange))
          : IndexedStack(
              index: tab,
              children: [_dashboard(), _myCards(), _assistant()],
            ),
      floatingActionButton: tab == 1
          ? FloatingActionButton.extended(
              onPressed: _chooseAddCard,
              backgroundColor: orange,
              foregroundColor: ink,
              icon: const Icon(Icons.add),
              label: const Text('Add card'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        backgroundColor: surface,
        indicatorColor: orange.withValues(alpha: .18),
        selectedIndex: tab,
        onDestinationSelected: (i) {
          setState(() => tab = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.credit_card_outlined),
            selectedIcon: Icon(Icons.credit_card),
            label: 'My Cards',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI Assistant',
          ),
        ],
      ),
    );
  }

  Widget _dashboard() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Your cards, working smarter.',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Know which card to use before you pay.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _metric(
                  '${cards.where((c) => c.active).length}',
                  'Active cards',
                  Icons.credit_card,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _metric(
                  '${cards.where((c) => !c.active).length}',
                  'Paused cards',
                  Icons.pause_circle_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _sectionTitle(
            'Your wallet',
            action: 'See all',
            onTap: () => setState(() => tab = 1),
          ),
          const SizedBox(height: 12),
          if (cards.where((c) => c.active).isEmpty)
            _empty(
              'Add your first card',
              'Keep your card benefits together and compare rewards.',
              Icons.wallet_outlined,
              button: 'Add a card',
              onTap: _editCard,
            )
          else
            SizedBox(
              height: 174,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cards.where((c) => c.active).length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _cardTile(
                    cards.where((c) => c.active).toList()[i],
                    width: 285),
              ),
            ),
          const SizedBox(height: 26),
          _sectionTitle(
            'Find the best card',
            action: 'Compare',
            onTap: () => setState(() => tab = 2),
          ),
          const SizedBox(height: 12),
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Planning a purchase?',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Compare estimated rewards across your cards.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => setState(() => tab = 2),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Find my best card'),
                    style: FilledButton.styleFrom(
                      backgroundColor: orange,
                      foregroundColor: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
  Widget _myCards() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        children: [
          const Text(
            'Your wallet',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '${cards.length} saved ${cards.length == 1 ? 'card' : 'cards'} · Stored on this device',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _browseCatalogue,
            icon: const Icon(Icons.travel_explore),
            label: const Text('Browse all 238 cards'),
            style: FilledButton.styleFrom(
              backgroundColor: orange,
              foregroundColor: ink,
            ),
          ),
          const SizedBox(height: 12),
          if (cards.isEmpty)
            _empty(
              'Your cards will live here',
              'Browse the card catalogue or enter your card details manually.',
              Icons.credit_card,
              button: 'Add your first card',
              onTap: _editCard,
            )
          else
            ...cards.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () => _cardDetails(e.value, e.key),
                      child: _cardTile(e.value, width: double.infinity),
                    ),
                  ),
                ),
        ],
      );
  Widget _assistant() => AiChatPage(cards: cards);
  Widget _metric(String value, String label, IconData icon) => _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: orange),
            const SizedBox(height: 13),
            Text(
              value,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
            ),
            Text(label, style: const TextStyle(color: muted)),
          ],
        ),
      );
  Widget _panel({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
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
              child: Text(action, style: const TextStyle(color: orange)),
            ),
        ],
      );
  Widget _cardTile(CreditCard c, {required double width}) => Container(
        width: width,
        height: 174,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF33302D), Color(0xFF1C1C1E)],
          ),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  c.bank.toUpperCase(),
                  style: const TextStyle(
                    color: muted,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const Icon(Icons.contactless, color: orange),
              ],
            ),
            const Spacer(),
            Text(
              c.nickname.isEmpty ? c.name : c.nickname,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${c.name} · ${c.network}',
              style: const TextStyle(color: muted, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 9),
            Text(
              c.active ? 'ACTIVE' : 'INACTIVE',
              style: TextStyle(
                color: c.active ? const Color(0xFF7DE0A1) : muted,
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
  Widget _empty(
    String title,
    String text,
    IconData icon, {
    String? button,
    VoidCallback? onTap,
  }) =>
      _panel(
        child: Column(
          children: [
            Icon(icon, size: 38, color: muted),
            const SizedBox(height: 13),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted),
            ),
            if (button != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onTap, child: Text(button)),
            ],
          ],
        ),
      );
  Future<void> _chooseAddCard() async {
    final choice = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: surface,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.search, color: orange),
            title: const Text('Browse the 238-card catalogue'),
            subtitle: const Text('Search by card, bank or feature'),
            onTap: () => Navigator.pop(ctx, true),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Enter card manually'),
            subtitle: const Text('Add a card that is not in the catalogue'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice) {
      await _browseCatalogue();
    } else {
      await _editCard();
    }
  }

  Future<void> _browseCatalogue() async {
    final entry = await Navigator.of(context).push<CardCatalogEntry>(
      MaterialPageRoute(builder: (_) => const CardCataloguePage()),
    );
    if (entry != null && mounted) await _editCard(catalogue: entry);
  }

  Future<void> _editCard({CreditCard? existing, int? index, CardCatalogEntry? catalogue}) async {
    final form = GlobalKey<FormState>();
    final catalogNotes = catalogue == null ? '' : [
      catalogue.summary,
      if (catalogue.details['Key Highlights']?.isNotEmpty == true) 'Key highlights: ${catalogue.details['Key Highlights']}',
      'Reference: ${catalogue.detailUrl}',
    ].where((value) => value.trim().isNotEmpty).join('\n\n');
    final catalogNetwork = (catalogue?.details['Network'] ?? '').toLowerCase();
    final prefNetwork = catalogNetwork.contains('mastercard') ? 'Mastercard'
        : catalogNetwork.contains('rupay') ? 'RuPay'
        : (catalogNetwork.contains('amex') || catalogNetwork.contains('american express')) ? 'American Express'
        : catalogNetwork.contains('visa') ? 'Visa' : 'Other';
    final bank = TextEditingController(text: existing?.bank ?? catalogue?.bank),
        name = TextEditingController(text: existing?.name ?? catalogue?.name),
        nick = TextEditingController(text: existing?.nickname),
        cats = TextEditingController(text: existing?.categories ?? catalogue?.category),
        notes = TextEditingController(text: existing?.notes ?? catalogNotes),
        cardNumber = TextEditingController(text: existing?.cardNumber ?? ''),
        expiry = TextEditingController(text: existing?.expiryDate ?? ''),
        cvv = TextEditingController(text: existing?.cvv ?? ''),
        fee = TextEditingController(text: '${existing?.annualFee ?? catalogue?.annualFee ?? 0}'),
        cash = TextEditingController(text: '${existing?.cashback ?? catalogue?.cashbackRate ?? 0}'),
        rate = TextEditingController(text: '${existing?.rewardRate ?? 0}'),
        point = TextEditingController(text: '${existing?.pointValue ?? 0}');
    String network = existing?.network ?? (catalogue == null ? 'Visa' : prefNetwork);
    bool stack = existing?.rewardsStack ?? false;
    bool revealNumber = false, revealCvv = false, showBack = false;
    Future<dynamic>? sheetTransitionCompleted;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      builder: (ctx) {
        sheetTransitionCompleted = ModalRoute.of(ctx)?.completed;
        return StatefulBuilder(
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        existing == null ? 'Add a card' : 'Edit card',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Text('Card details are encrypted and stored only on this device.', style: TextStyle(color: muted)),
                  const SizedBox(height: 16),
                  _cardPreview(
                    bank: bank.text,
                    name: name.text,
                    nickname: nick.text,
                    number: cardNumber.text,
                    expiry: expiry.text,
                    network: network,
                    showBack: showBack,
                    cvv: cvv.text,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setSheet(() => showBack = !showBack),
                      icon: Icon(showBack ? Icons.credit_card : Icons.flip),
                      label: Text(showBack ? 'Show front' : 'Show back'),
                    ),
                  ),
                  _paymentField(
                    cardNumber,
                    'Card number',
                    hint: '1234 5678 9012 3456',
                    required: existing == null || (existing.cardNumber.isNotEmpty),
                    obscure: !revealNumber,
                    onToggle: () => setSheet(() => revealNumber = !revealNumber),
                    onChanged: (_) => setSheet(() {}),
                    validator: (value) {
                      final digits = value?.replaceAll(RegExp(r'\D'), '') ?? '';
                      if (digits.isEmpty && existing != null) return null;
                      if (digits.length < 15 || digits.length > 19) return 'Enter 15–19 digits';
                      return null;
                    },
                    formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(19)],
                  ),
                  Row(children: [
                    Expanded(child: _paymentField(
                      expiry, 'Expiry date', hint: 'MM/YY', required: existing == null || (existing.expiryDate.isNotEmpty),
                      onChanged: (value) {
                        final digits = value.replaceAll(RegExp(r'\D'), '');
                        final formatted = digits.length > 2 ? '${digits.substring(0, 2)}/${digits.substring(2, digits.length.clamp(2, 4).toInt())}' : digits;
                        if (formatted != value) {
                          expiry.value = TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
                        }
                        setSheet(() {});
                      },
                      validator: (value) {
                        if ((value ?? '').isEmpty && existing != null) return null;
                        final match = RegExp(r'^(0[1-9]|1[0-2])/([0-9]{2})$').firstMatch(value ?? '');
                        if (match == null) return 'Use MM/YY';
                        final month = int.parse(match.group(1)!);
                        final year = 2000 + int.parse(match.group(2)!);
                        final now = DateTime.now();
                        if (year < now.year || (year == now.year && month < now.month)) return 'Card has expired';
                        return null;
                      },
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _paymentField(
                      cvv, 'CVV', hint: '•••', obscure: !revealCvv,
                      onToggle: () => setSheet(() => revealCvv = !revealCvv),
                      onChanged: (_) => setSheet(() {}),
                      validator: (value) => (value != null && value.isNotEmpty && !RegExp(r'^\d{3,4}$').hasMatch(value)) ? 'Enter 3–4 digits' : null,
                      formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    )),
                  ]),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('Card number, expiry, and CVV are encrypted on this device.', style: TextStyle(color: muted, fontSize: 12)),
                  ),
                  _field(bank, 'Bank or issuer'),
                  _field(name, 'Card name and variant'),
                  _field(nick, 'Nickname (optional)', required: false),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: network,
                    decoration: const InputDecoration(labelText: 'Network'),
                    items: [
                      'Visa',
                      'Mastercard',
                      'RuPay',
                      'American Express',
                      'Other',
                    ]
                        .map(
                          (n) => DropdownMenuItem(value: n, child: Text(n)),
                        )
                        .toList(),
                    onChanged: (v) => setSheet(() => network = v ?? 'Visa'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _field(fee, 'Annual fee (₹)', numeric: true),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(cash, 'Cashback (%)', numeric: true),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          rate,
                          'Reward points per ₹100',
                          numeric: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          point,
                          '₹ per point (estimate)',
                          numeric: true,
                        ),
                      ),
                    ],
                  ),
                  _field(
                    cats,
                    'Reward categories (comma separated)',
                    required: false,
                  ),
                  CheckboxListTile(
                    value: stack,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cashback and points can both apply'),
                    subtitle: const Text(
                      'Leave off unless your card terms confirm stacking.',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    onChanged: (v) => setSheet(() => stack = v ?? false),
                  ),
                  _field(
                    notes,
                    'Benefits, caps, exclusions and notes',
                    required: false,
                    maxLines: 3,
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
                        final card = CreditCard(
                          bank: bank.text.trim(),
                          name: name.text.trim(),
                          network: network,
                          nickname: nick.text.trim(),
                          annualFee: double.tryParse(fee.text) ?? 0,
                          cashback: double.tryParse(cash.text) ?? 0,
                          rewardRate: double.tryParse(rate.text) ?? 0,
                          pointValue: double.tryParse(point.text) ?? 0,
                          categories: cats.text.trim(),
                          notes: notes.text.trim(),
                          cardNumber: cardNumber.text.replaceAll(RegExp(r'\D'), ''),
                          expiryDate: expiry.text.trim(),
                          cvv: cvv.text.trim(),
                          secureDetails: existing?.secureDetails ?? '',
                          active: existing?.active ?? true,
                          rewardsStack: stack,
                        );
                        if (index == null) {
                          cards.add(card);
                        } else {
                          cards[index] = card;
                        }
                        // Remove focus first, then persist without rebuilding
                        // the parent while this modal Form is still mounted.
                        FocusManager.instance.primaryFocus?.unfocus();
                        await _save(notify: false);
                        if (!ctx.mounted) return;
                        await WidgetsBinding.instance.endOfFrame;
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: orange,
                        foregroundColor: ink,
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
        );
      },
    );
    final exitedSheet = sheetTransitionCompleted;
    if (exitedSheet != null) await exitedSheet;
    cvv.clear();
    for (final controller in [bank, name, nick, cats, notes, fee, cash, rate, point, cardNumber, expiry, cvv]) {
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
  }) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: obscure,
          onChanged: onChanged,
          inputFormatters: formatters,
          validator: validator ?? (value) => required && (value == null || value.isEmpty) ? 'Required' : null,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            suffixIcon: onToggle == null ? null : IconButton(
              onPressed: onToggle,
              icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
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
    required bool showBack,
    required String cvv,
  }) {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    final masked = digits.isEmpty
        ? '••••  ••••  ••••  ••••'
        : '••••  ••••  ••••  ${digits.length <= 4 ? digits : digits.substring(digits.length - 4)}';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      height: 204,
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
      child: showBack
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 14),
              Container(height: 38, color: Colors.black.withValues(alpha: .55)),
              const Spacer(),
              Row(children: [
                Expanded(child: Container(height: 34, color: Colors.white.withValues(alpha: .78))),
                const SizedBox(width: 10),
                Container(width: 54, height: 34, alignment: Alignment.center, color: Colors.white,
                  child: Text(cvv.isEmpty ? 'CVV' : '•••', style: const TextStyle(color: ink, fontWeight: FontWeight.bold))),
              ]),
              const SizedBox(height: 10),
              const Text('Stored securely on this device', style: TextStyle(fontSize: 11, color: Colors.white70)),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text(bank.isEmpty ? 'BANK / ISSUER' : bank.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.2))),
                const Icon(Icons.contactless, size: 27, color: Colors.white70),
              ]),
              const SizedBox(height: 15),
              const Icon(Icons.memory, size: 30, color: Color(0xFFFFD27A)),
              const SizedBox(height: 8),
              Text(masked, style: const TextStyle(fontSize: 18, letterSpacing: 1.3, fontFeatures: [FontFeature.tabularFigures()])),
              const Spacer(),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('CARDHOLDER', style: TextStyle(fontSize: 9, color: Colors.white60, letterSpacing: 1)),
                  Text((nickname.isNotEmpty ? nickname : name).isEmpty ? 'YOUR NAME' : (nickname.isNotEmpty ? nickname : name).toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('EXPIRES', style: TextStyle(fontSize: 9, color: Colors.white60, letterSpacing: 1)),
                  Text(expiry.isEmpty ? 'MM/YY' : expiry),
                ]),
                const SizedBox(width: 16),
                Text(network.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ]),
            ]),
    );
  }

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
    final lastFour = digits.length > 4 ? digits.substring(digits.length - 4) : digits;
    showModalBottomSheet(
        context: context,
        backgroundColor: surface,
        isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setDetails) => SafeArea(
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
                _cardPreview(
                  bank: c.bank,
                  name: c.name,
                  nickname: c.nickname,
                  number: c.cardNumber,
                  expiry: c.expiryDate,
                  network: c.network,
                  showBack: showBack,
                  cvv: c.cvv,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setDetails(() => showBack = !showBack),
                    icon: Icon(showBack ? Icons.credit_card : Icons.flip),
                    label: Text(showBack ? 'Show front' : 'Show back'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  c.name,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${c.bank} · ${c.network}',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Text(digits.isEmpty
                      ? 'Card number not entered'
                      : revealNumber
                          ? digits.replaceAllMapped(RegExp(r'.{4}'), (m) => '${m.group(0)} ').trim()
                          : '•••• •••• •••• $lastFour')),
                  if (digits.isNotEmpty)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: revealNumber ? 'Hide card number' : 'Show card number',
                        onPressed: () => setDetails(() => revealNumber = !revealNumber),
                        icon: Icon(revealNumber ? Icons.visibility_off : Icons.visibility),
                      ),
                      IconButton(
                        tooltip: 'Copy card number',
                        onPressed: () => _copyCardDetail(digits, 'Card number'),
                        icon: const Icon(Icons.copy),
                      ),
                    ]),
                ]),
                Row(children: [
                  Expanded(child: Text('Expiry date  ${c.expiryDate.isEmpty ? 'Not entered' : c.expiryDate}')),
                  if (c.expiryDate.isNotEmpty)
                    IconButton(
                      tooltip: 'Copy expiry date',
                      onPressed: () => _copyCardDetail(c.expiryDate, 'Expiry date'),
                      icon: const Icon(Icons.copy),
                    ),
                ]),
                Row(children: [
                  Expanded(child: Text('CVV  ${c.cvv.isEmpty ? 'Not entered' : revealCvv ? c.cvv : '•••'}')),
                  if (c.cvv.isNotEmpty) ...[
                    IconButton(
                      tooltip: revealCvv ? 'Hide CVV' : 'Show CVV',
                      onPressed: () => setDetails(() => revealCvv = !revealCvv),
                      icon: Icon(revealCvv ? Icons.visibility_off : Icons.visibility),
                    ),
                    IconButton(
                      tooltip: 'Copy CVV',
                      onPressed: () => _copyCardDetail(c.cvv, 'CVV'),
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ]),
                const SizedBox(height: 14),
                Text('Annual fee  ₹${c.annualFee.toStringAsFixed(0)}'),
                Text('Cashback  ${c.cashback}%'),
                Text(
                  'Rewards  ${c.rewardRate} pts / ₹100 · ₹${c.pointValue} per point',
                ),
                if (c.categories.isNotEmpty)
                  Text('Categories  ${c.categories}'),
                if (c.notes.isNotEmpty) Text(c.notes),
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
                        c.active = !c.active;
                        await _save();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: Text(c.active ? 'Deactivate' : 'Reactivate'),
                    ),
                    TextButton(
                      onPressed: () async {
                        cards.removeAt(i);
                        await _save();
                        if (ctx.mounted) Navigator.pop(ctx);
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
        )),
      );
  }

  Future<void> _copyCardDetail(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  void _search() => showSearch(
        context: context,
        delegate: _CardSearch(cards, (c) => setState(() => tab = 1)),
      );
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

class _AssistantView extends StatefulWidget {
  const _AssistantView({required this.cards});
  final List<CreditCard> cards;
  @override
  State<_AssistantView> createState() => _AssistantViewState();
}

class _AssistantViewState extends State<_AssistantView> {
  final amount = TextEditingController();
  final merchant = TextEditingController();
  List<_Result> results = [];
  bool calculated = false;
  void _calculate() {
    final spend = double.tryParse(amount.text.replaceAll(',', '')) ?? 0;
    if (spend <= 0 || widget.cards.where((c) => c.active).isEmpty) {
      setState(() => calculated = true);
      return;
    }
    final active = widget.cards.where((c) => c.active).toList();
    results = active.map((c) {
      final cashback = spend * c.cashback / 100;
      final points = spend / 100 * c.rewardRate * c.pointValue;
      final estimated = c.rewardsStack
          ? cashback + points
          : (cashback > points ? cashback : points);
      return _Result(c, estimated, cashback, points, spend - estimated);
    }).toList()
      ..sort((a, b) => b.savings.compareTo(a.savings));
    setState(() => calculated = true);
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Best card finder',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Estimate rewards from the rates you entered.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: merchant,
            decoration: const InputDecoration(
              labelText: 'Merchant or category',
              hintText: 'e.g. groceries, travel',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Purchase amount (₹)',
              hintText: 'e.g. 20000',
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _calculate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Compare my cards'),
              style: FilledButton.styleFrom(
                backgroundColor: orange,
                foregroundColor: ink,
              ),
            ),
          ),
          if (calculated) ...[
            const SizedBox(height: 20),
            if (results.isEmpty)
              const Text(
                'Add an active card and a valid purchase amount to compare.',
                style: TextStyle(color: muted),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: orange.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Estimate based only on the rates you entered. Unconfirmed cashback and points are not added together. Caps, eligibility, exclusions and fees are not applied.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 12),
              ...results.asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (e.key == 0)
                                  const Icon(
                                    Icons.emoji_events,
                                    color: orange,
                                    size: 19,
                                  ),
                                if (e.key == 0) const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    e.value.card.nickname.isEmpty
                                        ? e.value.card.name
                                        : e.value.card.nickname,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Text(
                                  '₹${e.value.savings.toStringAsFixed(0)} est.',
                                  style: const TextStyle(
                                    color: Color(0xFF7DE0A1),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Cashback rule ₹${e.value.cashback.toStringAsFixed(0)} · Points rule ₹${e.value.points.toStringAsFixed(0)} · Counted savings ₹${e.value.savings.toStringAsFixed(0)} · Estimated cost ₹${e.value.cost.toStringAsFixed(0)}',
                              style:
                                  const TextStyle(color: muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        ],
      );
}

class _Result {
  _Result(this.card, this.savings, this.cashback, this.points, this.cost);
  final CreditCard card;
  final double savings, cashback, points, cost;
}

class _CardSearch extends SearchDelegate<void> {
  _CardSearch(this.cards, this.onPick);
  final List<CreditCard> cards;
  final ValueChanged<CreditCard> onPick;
  @override
  String get searchFieldLabel => 'Search cards and benefits';
  @override
  List<Widget> buildActions(BuildContext c) => [
        IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
      ];
  @override
  Widget buildLeading(BuildContext c) => IconButton(
        onPressed: () => close(c, null),
        icon: const Icon(Icons.arrow_back),
      );
  @override
  Widget buildResults(BuildContext c) => buildSuggestions(c);
  @override
  Widget buildSuggestions(BuildContext c) {
    final q = query.toLowerCase();
    final matches = cards
        .where(
          (x) => '${x.bank} ${x.name} ${x.nickname} ${x.categories} ${x.notes}'
              .toLowerCase()
              .contains(q),
        )
        .toList();
    return ListView(
      children: matches
          .map(
            (x) => ListTile(
              leading: const Icon(Icons.credit_card, color: orange),
              title: Text(x.nickname.isEmpty ? x.name : x.nickname),
              subtitle: Text('${x.bank} · ${x.categories}'),
              onTap: () {
                onPick(x);
                close(c, null);
              },
            ),
          )
          .toList(),
    );
  }
}
