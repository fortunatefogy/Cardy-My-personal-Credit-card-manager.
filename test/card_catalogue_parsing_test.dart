import 'package:flutter_test/flutter_test.dart';

import 'package:cardy/features/cards/card_catalogue.dart';
import 'package:cardy/features/cards/card_catalogue_service.dart';

void main() {
  group('robots.txt parser', () {
    test('allows paths not covered by disallow rules', () {
      const robots = 'User-agent: *\nAllow: /\nDisallow: /private/';
      expect(CardCatalogueService.robotsAllows(robots, '/cards/'), isTrue);
    });

    test('disallows paths covered by rules', () {
      const robots = 'User-agent: *\nDisallow: /private/';
      expect(CardCatalogueService.robotsAllows(robots, '/private/x'), isFalse);
    });

    test('allows everything when no matching group exists', () {
      const robots = 'User-agent: SomeBot\nDisallow: /';
      expect(CardCatalogueService.robotsAllows(robots, '/cards/'), isTrue);
    });
  });

  group('client data feed', () {
    final data = [
      {
        's': 'hdfc-infinia',
        'n': 'HDFC Infinia',
        'b': 'HDFC',
        'sc': 8.9,
        'af': 12500,
        'fx': 2,
        'cat': 'super-premium',
        'h': ['Unlimited lounge access'],
        'lg': -1,
      },
      {
        's': 'hdfc-bharat-cashback',
        'n': 'HDFC Bharat Cashback',
        'b': 'HDFC',
        'sc': 7.4,
        'af': 500,
        'fx': 3.5,
        'cat': 'cashback',
        'h': ['5% cashback'],
        'lg': 0,
      },
      {'s': '', 'n': 'Broken entry', 'b': ''},
    ];

    test('maps feed fields into catalogue entries', () {
      final entries = CardCatalogueService.clientEntriesFromJson(data);
      expect(entries, hasLength(2));
      final infinia = entries.first;
      expect(infinia.slug, 'hdfc-infinia');
      expect(infinia.name, 'HDFC Infinia');
      expect(infinia.bank, 'HDFC');
      expect(infinia.category, 'Super Premium');
      expect(infinia.annualFee, 12500);
      expect(infinia.forexMarkup, 2);
      expect(infinia.cardTrailScore, 8.9);
      expect(infinia.detailUrl, 'https://cardtrail.in/cards/hdfc-infinia/');
      expect(infinia.details['Lounge Access'], 'Unlimited');
      expect(infinia.details['Key Highlights'], 'Unlimited lounge access');
    });

    test('parses fee strings without commas', () {
      final bharat = CardCatalogueService.clientEntriesFromJson(data).last;
      expect(bharat.category, 'Cashback');
      expect(bharat.details['Lounge Access'], '0 visit(s)');
      expect(bharat.cashbackRate, isNull);
    });
  });

  group('detail page parsing', () {
    const html = '''
    <html><body>
    <h1>Test Platinum</h1>
    Scored across rewards and fees Compare This Card Save Full Details
    Annual Fee ₹12,500 Spend ₹10L/year Forex Markup 2% Reward Rate 3.33%
    Up to 33.3% Lounge Access Unlimited domestic
    About This Card A premium travel card with lounge perks.
    Pros & Cons Pros Excellent lounge access included Cons High fee invite model
    Fee Details Annual Fee ₹12,500 Joining Fee ₹12,500 Fee Waiver Condition
    Spend ₹10L/year Fuel Surcharge Waiver Yes EMI Conversion Yes
    Reward Structure Base Rate 3.33% Max Rate 33.3% Currency Reward Points
    Welcome Bonus 5,000 points (first year) Lounge Access
    Domestic Lounges Unlimited International Lounges 8
    Key Highlights Unlimited lounge access 3.33% base reward rate
    Compare With... Another Card CardTrail Score 9.0
    Best For travel luxury Annual Fee ₹12,500 Base Reward 3.33%
    Forex Markup 2% Network Visa Infinite Min Income Not published
    Compare This Card CardTrail Score 8.9 / 10 Scored across rewards.
    </body></html>
    ''';

    test('captures unlimited and numeric lounges', () {
      final entry = CardCatalogueService.parseDetails(
          html,
          const CardCatalogEntry(
            slug: 'test-platinum',
            name: 'Test Platinum',
            bank: 'HDFC Bank',
            detailUrl: 'https://cardtrail.in/cards/test-platinum/',
          ));
      expect(entry.details['Domestic Lounges'], 'Unlimited');
      expect(entry.details['International Lounges'], '8');
    });

    test('captures structured fields', () {
      final entry = CardCatalogueService.parseDetails(
          html,
          const CardCatalogEntry(
            slug: 'test-platinum',
            name: 'Test',
            bank: 'HDFC Bank',
            detailUrl: 'https://cardtrail.in/cards/test-platinum/',
          ));
      expect(entry.details['Annual Fee'], '₹12,500');
      expect(entry.details['Joining Fee'], '₹12,500');
      expect(entry.details['Fee Waiver Condition'], 'Spend ₹10L/year');
      expect(entry.details['Base Reward Rate'], '3.33%');
      expect(entry.details['Maximum Reward Rate'], '33.3%');
      expect(entry.details['Reward Currency'], 'Reward Points');
      expect(entry.details['Welcome Bonus'], '5,000 points (first year)');
      expect(entry.details['Network'], 'Visa Infinite');
      expect(entry.details['Minimum Income'], 'Not published');
      expect(entry.details['Best For'], 'travel luxury');
      expect(entry.details['CardTrail Score'], '8.9 / 10');
      expect(entry.details['Fuel Surcharge Waiver'], 'Yes');
      expect(entry.details['EMI Conversion'], 'Yes');
      expect(entry.summary, contains('premium travel card'));
      expect(entry.name, 'Test Platinum');
      expect(entry.details['Pros & Cons'], isNotEmpty);
      expect(entry.details['Key Highlights'], contains('Unlimited'));
    });
  });

  group('catalogue page parsing', () {
    const html = '''
    <html><body>
    <a href="https://cardtrail.in/cards/hdfc-infinia/">HDFC Infinia</a>
    <a href="https://cardtrail.in/cards/">Cards Index</a>
    <a href="https://example.com/cards/other/">External</a>
    </body></html>
    ''';

    test('only keeps trusted card links with real slugs', () {
      final entries = CardCatalogueService.parseCatalogue(html);
      expect(entries, hasLength(1));
      expect(entries.single.slug, 'hdfc-infinia');
      expect(entries.single.bank, 'HDFC Bank');
    });
  });

  group('entry accessors', () {
    const entry = CardCatalogEntry(
      slug: 'x',
      name: 'X Card',
      bank: 'Axis Bank',
      detailUrl: 'u',
      category: 'Cashback',
      details: {
        'Annual Fee': '₹1,499',
        'Forex Markup': '3.5%',
        'Base Reward Rate': '1.5%',
        'CardTrail Score': '7.4 / 10',
      },
    );

    test('parses money, percent and score', () {
      expect(entry.annualFee, 1499);
      expect(entry.forexMarkup, 3.5);
      expect(entry.cardTrailScore, 7.4);
    });

    test('cashback rate uses base reward rate for cashback category', () {
      expect(entry.cashbackRate, 1.5);
    });

    test('non-cashback cards without cashback wording return null', () {
      const entry = CardCatalogEntry(
        slug: 'y',
        name: 'Y Card',
        bank: 'Axis Bank',
        detailUrl: 'u',
        category: 'Travel',
        details: {'Base Reward Rate': '3.33%'},
      );
      expect(entry.cashbackRate, isNull);
    });
  });
}
