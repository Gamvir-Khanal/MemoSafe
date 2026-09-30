import 'package:firebase_auth/firebase_auth.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'note_type.dart';
import 'security_service.dart';

class NoteModel {
  final int? sNo;
  final String title;
  final String desc;
  final String? mImagePath; // JSON-encoded list of image paths
  final String? mAudioPath; // JSON-encoded list of audio paths
  final String? mChecklist; // JSON-encoded list of ChecklistItem
  final String? mDrawingPath; // JSON-encoded list of DrawStroke
  final NoteType mType;
  final NoteStatus mStatus;
  final int sortOrder; // 0 = unset (falls back to s_no order)
  final bool isPinned;
  final String? userId;
  /// Last time this note was saved. Stored as ISO-8601 UTC string in SQLite.
  final DateTime? updatedAt;

  NoteModel({
    this.sNo,
    required this.title,
    this.desc = '',
    this.mImagePath,
    this.mAudioPath,
    this.mChecklist,
    this.mDrawingPath,
    required this.mType,
    this.mStatus = NoteStatus.normal,
    this.sortOrder = 0,
    this.isPinned = false,
    this.userId,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    final uid = userId ?? FirebaseAuth.instance.currentUser?.uid;
    return {
      if (sNo != null) 's_no': sNo,
      'title': title,
      'desc': desc,
      'mImagePath': mImagePath,
      'mAudioPath': mAudioPath,
      'mChecklist': mChecklist,
      'mDrawingPath': mDrawingPath,
      'mType': mType.dbValue,
      'mStatus': mStatus.dbValue,
      'sortOrder': sortOrder,
      'isPinned': isPinned ? 1 : 0,
      'userId': uid,
      // Always write the current timestamp when persisting.
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
  }

  factory NoteModel.fromMap(Map<String, dynamic> map) {
    DateTime? parsedDate;
    final rawDate = map['updated_at'] as String?;
    if (rawDate != null && rawDate.isNotEmpty) {
      parsedDate = DateTime.tryParse(rawDate)?.toLocal();
    }
    return NoteModel(
      sNo: map['s_no'] as int?,
      title: map['title'] ?? '',
      desc: map['desc'] ?? '',
      mImagePath: map['mImagePath'],
      mAudioPath: map['mAudioPath'],
      mChecklist: map['mChecklist'],
      mDrawingPath: map['mDrawingPath'],
      mType: NoteTypeX.fromDb(map['mType']),
      mStatus: NoteStatusX.fromDb(map['mStatus']),
      sortOrder: (map['sortOrder'] as int?) ?? 0,
      isPinned: (map['isPinned'] as int?) == 1,
      userId: map['userId'] as String?,
      updatedAt: parsedDate,
    );
  }

  NoteModel copyWith({
    NoteStatus? mStatus,
    int? sortOrder,
    bool? isPinned,
    String? userId,
    DateTime? updatedAt,
  }) {
    return NoteModel(
      sNo: sNo,
      title: title,
      desc: desc,
      mImagePath: mImagePath,
      mAudioPath: mAudioPath,
      mChecklist: mChecklist,
      mDrawingPath: mDrawingPath,
      mType: mType,
      mStatus: mStatus ?? this.mStatus,
      sortOrder: sortOrder ?? this.sortOrder,
      isPinned: isPinned ?? this.isPinned,
      userId: userId ?? this.userId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class DBHelper {
  DBHelper._internal();
  static final DBHelper instance = DBHelper._internal();

  static Database? _db;

  static const String tableName = 'note';
  static const int _dbVersion = 8;

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableName (
        s_no INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        desc TEXT,
        mImagePath TEXT,
        mAudioPath TEXT,
        mChecklist TEXT,
        mType TEXT,
        mStatus TEXT DEFAULT 'normal',
        sortOrder INTEGER DEFAULT 0,
        mDrawingPath TEXT,
        isPinned INTEGER DEFAULT 0,
        userId TEXT,
        updated_at TEXT
      )
    ''');
  }

  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE $tableName ADD COLUMN mImagePath TEXT');
      await db.execute('ALTER TABLE $tableName ADD COLUMN mAudioPath TEXT');
      await db.execute('ALTER TABLE $tableName ADD COLUMN mChecklist TEXT');
    }
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE $tableName ADD COLUMN mType TEXT DEFAULT 'text'",
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        "ALTER TABLE $tableName ADD COLUMN mStatus TEXT DEFAULT 'normal'",
      );
    }
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN sortOrder INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE $tableName ADD COLUMN mDrawingPath TEXT');
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN isPinned INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE $tableName ADD COLUMN userId TEXT');
    }
    if (oldVersion < 8) {
      await db.execute('ALTER TABLE $tableName ADD COLUMN updated_at TEXT');
    }
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'notes.db');
    final dbKey = await SecurityService.instance.getDatabaseKey();

    try {
      return await openDatabase(
        path,
        password: dbKey,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (_) {
      try {
        final unencryptedDb = await openDatabase(
          path,
          version: _dbVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
        await unencryptedDb.execute("PRAGMA key = ''");
        await unencryptedDb.execute("PRAGMA rekey = '$dbKey'");
        await unencryptedDb.close();
      } catch (_) {}

      return await openDatabase(
        path,
        password: dbKey,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }
  }

  String _orderByClause(NoteSortOption sort) {
    const pinnedFirst = 'isPinned DESC';
    switch (sort) {
      case NoteSortOption.newest:
        return '$pinnedFirst, s_no DESC';
      case NoteSortOption.oldest:
        return '$pinnedFirst, s_no ASC';
      case NoteSortOption.manual:
        return '$pinnedFirst, CASE WHEN sortOrder = 0 THEN s_no ELSE sortOrder END ASC';
    }
  }

  /// Returns ALL notes for the current user regardless of status.
  /// Used to backfill Firestore with correct vault/archive statuses.
  Future<List<NoteModel>> getAllNotes() async {
    final uid = _currentUid;
    if (uid == null) return [];

    final db = await database;
    final rows = await db.query(
      tableName,
      where: 'userId = ?',
      whereArgs: [uid],
      orderBy: 's_no DESC',
    );
    return rows.map((e) => NoteModel.fromMap(e)).toList();
  }

  /// Notes visible on the main Home page for the current logged-in user.
  Future<List<NoteModel>> getNotes({
    String? query,
    NoteSortOption sort = NoteSortOption.newest,
  }) async {
    final uid = _currentUid;
    if (uid == null) return [];

    final db = await database;
    final conditions = <String>[
      '(mStatus IS NULL OR mStatus = ?)',
      'userId = ?',
    ];
    final args = <Object?>[NoteStatus.normal.dbValue, uid];

    final trimmed = query?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      final like = '%$trimmed%';
      conditions.add('(title LIKE ? OR desc LIKE ? OR mChecklist LIKE ?)');
      args.addAll([like, like, like]);
    }

    final rows = await db.query(
      tableName,
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: _orderByClause(sort),
    );
    return rows.map((e) => NoteModel.fromMap(e)).toList();
  }

  /// Notes filed under a given status (archive / vault) for current user.
  Future<List<NoteModel>> getNotesByStatus(NoteStatus status) async {
    final uid = _currentUid;
    if (uid == null) return [];

    final db = await database;
    final rows = await db.query(
      tableName,
      where: 'mStatus = ? AND userId = ?',
      whereArgs: [status.dbValue, uid],
      orderBy: 'isPinned DESC, s_no DESC',
    );
    return rows.map((e) => NoteModel.fromMap(e)).toList();
  }

  /// Count by status for current user.
  Future<int> countByStatus(NoteStatus status) async {
    final uid = _currentUid;
    if (uid == null) return 0;

    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $tableName WHERE mStatus = ? AND userId = ?',
      [status.dbValue, uid],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> addNote(NoteModel note) async {
    final db = await database;
    return db.insert(tableName, note.toMap());
  }

  /// Inserts or replaces a note by primary key. Safe to call on reinstall sync
  /// so remote notes never create duplicates in a fresh local database.
  Future<int> upsertNote(NoteModel note) async {
    final db = await database;
    return db.insert(
      tableName,
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateNote(NoteModel note) async {
    final db = await database;
    return db.update(
      tableName,
      note.toMap(),
      where: 's_no = ? AND userId = ?',
      whereArgs: [note.sNo, _currentUid],
    );
  }

  Future<int> updateStatus(int sNo, NoteStatus status) async {
    final db = await database;
    return db.update(
      tableName,
      {'mStatus': status.dbValue},
      where: 's_no = ? AND userId = ?',
      whereArgs: [sNo, _currentUid],
    );
  }

  Future<int> updatePinned(int sNo, bool pinned) async {
    final db = await database;
    return db.update(
      tableName,
      {'isPinned': pinned ? 1 : 0},
      where: 's_no = ? AND userId = ?',
      whereArgs: [sNo, _currentUid],
    );
  }

  Future<void> updateSortOrders(List<int> orderedSNos) async {
    final db = await database;
    final batch = db.batch();
    for (var i = 0; i < orderedSNos.length; i++) {
      batch.update(
        tableName,
        {'sortOrder': i + 1},
        where: 's_no = ? AND userId = ?',
        whereArgs: [orderedSNos[i], _currentUid],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> deleteNote(int sNo) async {
    final db = await database;
    return db.delete(
      tableName,
      where: 's_no = ? AND userId = ?',
      whereArgs: [sNo, _currentUid],
    );
  }

  /// Wipes all local notes from the device (e.g. on logout for privacy).
  Future<void> clearAllLocalNotes() async {
    final db = await database;
    await db.delete(tableName);
  }
}
