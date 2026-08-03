import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalDatabase {
  LocalDatabase._internal();
  static final LocalDatabase instance = LocalDatabase._internal();

  late final Database db;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    sqfliteFfiInit();
    final databaseFactory = databaseFactoryFfi;
    final applicationDir = await getApplicationSupportDirectory();
    final databasePath = path.join(applicationDir.path, 'eldn_edge_server.db');

    db = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );

    await _ensureDefaultAdmin();
    _initialized = true;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tb_nodes(
        node_id TEXT PRIMARY KEY,
        status_alat TEXT,
        last_seen TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS tb_sensor_logs(
        log_id INTEGER PRIMARY KEY AUTOINCREMENT,
        node_id TEXT,
        latitude REAL,
        longitude REAL,
        suara_val INTEGER,
        getaran_count INTEGER,
        status_sys TEXT,
        vibration_status TEXT,
        sound_status TEXT,
        timestamp TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS tb_users_lokal(
        user_id TEXT PRIMARY KEY,
        username TEXT,
        password TEXT,
        role TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final tableExists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='tb_sensor_logs'",
      );
      if (tableExists.isNotEmpty) {
        final columns = await db.rawQuery("PRAGMA table_info(tb_sensor_logs)");
        final existingColumns = columns
            .map((column) => column['name'].toString())
            .toSet();

        if (!existingColumns.contains('status_sys')) {
          await db.execute(
            'ALTER TABLE tb_sensor_logs ADD COLUMN status_sys TEXT',
          );
        }
        if (!existingColumns.contains('vibration_status')) {
          await db.execute(
            'ALTER TABLE tb_sensor_logs ADD COLUMN vibration_status TEXT',
          );
        }
        if (!existingColumns.contains('sound_status')) {
          await db.execute(
            'ALTER TABLE tb_sensor_logs ADD COLUMN sound_status TEXT',
          );
        }
      }
    }
  }

  Future<void> _ensureDefaultAdmin() async {
    await db.insert('tb_users_lokal', {
      'user_id': 'admin',
      'username': 'admin',
      'password': 'admin123',
      'role': 'admin',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<int> insertSensorLog(Map<String, dynamic> values) async {
    return db.insert(
      'tb_sensor_logs',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> upsertNodeStatus({
    required String nodeId,
    required String statusAlat,
    required String lastSeen,
  }) async {
    return db.insert('tb_nodes', {
      'node_id': nodeId,
      'status_alat': statusAlat,
      'last_seen': lastSeen,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> findNode(String nodeId) async {
    final rows = await db.query(
      'tb_nodes',
      where: 'node_id = ?',
      whereArgs: [nodeId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<List<Map<String, dynamic>>> queryNodes() async {
    return db.query('tb_nodes', orderBy: 'last_seen DESC');
  }

  Future<List<Map<String, dynamic>>> queryLogs({int limit = 100}) async {
    return db.query('tb_sensor_logs', orderBy: 'timestamp DESC', limit: limit);
  }

  Future<Map<String, dynamic>?> findUser({
    required String username,
    required String password,
  }) async {
    final results = await db.query(
      'tb_users_lokal',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
      limit: 1,
    );

    if (results.isEmpty) {
      return null;
    }
    return results.first;
  }
}
