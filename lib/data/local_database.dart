import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();
  late final Future<Database> database = _open();

  Future<Database> _open() async {
    final directory = await getDatabasesPath();
    return openDatabase(
      p.join(directory, 'cardwise.db'),
      version: 16,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA secure_delete = ON');
      },
      onCreate: (db, version) async {
        await _createCardsTable(db);
        await _createCardCatalogueTable(db);
        await _createDebitCardsTable(db);
        await _createIdentityTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _createCardsTable(db);
        await _createCardCatalogueTable(db);
        await _createDebitCardsTable(db);
        await _createIdentityTable(db);
        if (oldVersion < 8) {
          await db.execute(
              "ALTER TABLE cards ADD COLUMN secure_details TEXT NOT NULL DEFAULT ''");
        }
        if (oldVersion < 9) {
          await db.execute(
              'ALTER TABLE cards ADD COLUMN style_seed INTEGER NOT NULL DEFAULT -1');
        }
        if (oldVersion < 10) {
          await db.execute('ALTER TABLE cards ADD COLUMN artwork_path TEXT');
        }
        if (oldVersion < 11) {
          await db.execute(
              'ALTER TABLE cards ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 13) {
          await db.execute(
              "ALTER TABLE debit_cards ADD COLUMN network TEXT NOT NULL DEFAULT ''");
          await db
              .execute('ALTER TABLE debit_cards ADD COLUMN artwork_path TEXT');
        }
        if (oldVersion < 14) {
          await db.execute(
              'ALTER TABLE debit_cards ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 16) {
          await db.execute(
              "ALTER TABLE identity_documents ADD COLUMN secure_details TEXT NOT NULL DEFAULT ''");
          await db.execute(
              'ALTER TABLE identity_documents ADD COLUMN artwork_path TEXT');
        }
      },
    );
  }

  Future<void> _createCardsTable(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS cards (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bank TEXT NOT NULL,
      name TEXT NOT NULL,
      network TEXT NOT NULL,
      nickname TEXT NOT NULL DEFAULT '',
      annual_fee REAL NOT NULL DEFAULT 0,
      cashback REAL NOT NULL DEFAULT 0,
      reward_rate REAL NOT NULL DEFAULT 0,
      point_value REAL NOT NULL DEFAULT 0,
      categories TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
      rewards_stack INTEGER NOT NULL DEFAULT 0 CHECK (rewards_stack IN (0, 1)),
      secure_details TEXT NOT NULL DEFAULT '',
      style_seed INTEGER NOT NULL DEFAULT -1,
      artwork_path TEXT,
      is_favorite INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0, 1))
    )
  ''');

  Future<void> _createCardCatalogueTable(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS card_catalogue (
      slug TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      bank TEXT NOT NULL DEFAULT '',
      detail_url TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT '',
      summary TEXT NOT NULL DEFAULT '',
      details_json TEXT NOT NULL DEFAULT '{}',
      checked_at INTEGER NOT NULL,
      details_checked_at INTEGER
    )
  ''');

  Future<void> _createIdentityTable(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS identity_documents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      doc_type TEXT NOT NULL,
      holder TEXT NOT NULL DEFAULT '',
      expiry TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      secure_details TEXT NOT NULL DEFAULT '',
      artwork_path TEXT,
      created_at INTEGER NOT NULL
    )
  ''');

  Future<void> _createDebitCardsTable(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS debit_cards (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bank TEXT NOT NULL,
      label TEXT NOT NULL DEFAULT '',
      holder TEXT NOT NULL DEFAULT '',
      last_four TEXT NOT NULL DEFAULT '',
      network TEXT NOT NULL DEFAULT '',
      secure_details TEXT NOT NULL DEFAULT '',
      artwork_path TEXT,
      is_favorite INTEGER NOT NULL DEFAULT 0 CHECK (is_favorite IN (0, 1)),
      created_at INTEGER NOT NULL
    )
  ''');
}
