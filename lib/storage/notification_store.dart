import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class NotificationInsertResult {
  final int id;
  final bool inserted;
  const NotificationInsertResult({required this.id, required this.inserted});
}

class NotificationStore {
  NotificationStore._();
  static final NotificationStore instance = NotificationStore._();
  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(p.join(dbPath, 'aegis.db'), version: 2, onCreate: (db, version) async {
      await db.execute('''CREATE TABLE notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT, package_name TEXT NOT NULL, app_name TEXT NOT NULL,
        title TEXT NOT NULL, text TEXT NOT NULL, timestamp_ms INTEGER NOT NULL, risk_score INTEGER,
        risk_level TEXT, scam_type TEXT, has_suspicious_link INTEGER NOT NULL DEFAULT 0,
        content_signature TEXT NOT NULL, repeat_count INTEGER NOT NULL DEFAULT 1, user_feedback TEXT)''');
      await db.execute('CREATE INDEX idx_signature ON notifications(content_signature)');
      await db.execute('CREATE INDEX idx_timestamp ON notifications(timestamp_ms)');
    }, onUpgrade: (db, oldVersion, newVersion) async {
    });
    return _db!;
  }

  static String signatureFor({required String packageName, required String title, required String text}) =>
      '$packageName|${title.trim().toLowerCase()}|${text.trim().toLowerCase()}';

  Future<Map<String, Object?>?> findBySignature(String signature) async {
    final rows = await (await _database).query('notifications', where: 'content_signature = ?', whereArgs: [signature], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<NotificationInsertResult> insertOrBump(Map<String, Object?> row) async {
    final db = await _database;
    return db.transaction((transaction) async {
      final signature = row['content_signature'];
      if (signature is String) {
        final rows = await transaction.query(
          'notifications',
          where: 'content_signature = ?',
          whereArgs: [signature],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final id = rows.first['id'] as int;
          await transaction.rawUpdate(
            'UPDATE notifications SET repeat_count = repeat_count + 1, timestamp_ms = ? WHERE id = ?',
            [row['timestamp_ms'], id],
          );
          return NotificationInsertResult(id: id, inserted: false);
        }
      }
      final id = await transaction.insert('notifications', row);
      return NotificationInsertResult(id: id, inserted: true);
    });
  }

  Future<void> bumpRepeat(int id, int timestampMs) async => (await _database).rawUpdate(
        'UPDATE notifications SET repeat_count = repeat_count + 1, timestamp_ms = ? WHERE id = ?', [timestampMs, id]);

  Future<void> setFeedback(int id, String? feedback) async => (await _database).update(
        'notifications', {'user_feedback': feedback}, where: 'id = ?', whereArgs: [id]);

  Future<List<Map<String, Object?>>> recent({int limit = 500}) async =>
      (await _database).query('notifications', orderBy: 'timestamp_ms DESC', limit: limit);

  Future<List<int>> dailyCounts(int days) async {
    if (days <= 0) return <int>[];
    final db = await _database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = today.subtract(Duration(days: days - 1));
    final rows = await db.rawQuery(
      '''SELECT date(timestamp_ms / 1000, 'unixepoch', 'localtime') AS day,
                COUNT(*) AS c
         FROM notifications
         WHERE timestamp_ms >= ?
         GROUP BY day
         ORDER BY day ASC''',
      [first.millisecondsSinceEpoch],
    );
    final byDay = <String, int>{
      for (final row in rows) '${row['day']}' : (row['c'] as num).toInt(),
    };
    return List<int>.generate(days, (index) {
      final day = first.add(Duration(days: index));
      final key = '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';
      return byDay[key] ?? 0;
    });
  }

  Future<String> exportFeedbackCsv() async {
    final rows = await (await _database).query('notifications', where: 'user_feedback IS NOT NULL', orderBy: 'timestamp_ms DESC');
    final buffer = StringBuffer('message_text,category,subcategory,platform_found,source_url,language,label,is_synthetic\n');
    for (final row in rows) {
      final message = [row['title'] as String? ?? '', row['text'] as String? ?? ''].where((s) => s.trim().isNotEmpty).join('. ');
      final feedback = row['user_feedback'] as String?;
      buffer.writeln([_csvEscape(message), 'User_Feedback', 'User_Corrected', _csvEscape(row['app_name'] as String? ?? 'Unknown'),
        'user_feedback', 'English', feedback == 'scam' ? '1' : '0', 'False'].join(','));
    }
    return buffer.toString();
  }

  String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    return value.contains(',') || value.contains('"') || value.contains('\n') ? '"$escaped"' : escaped;
  }
}