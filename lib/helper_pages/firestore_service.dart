import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'db_helper.dart';

class FirestoreService {
  FirestoreService._internal();
  static final FirestoreService instance = FirestoreService._internal();

  /// Returns a FirebaseFirestore instance, or null if Firebase is not initialized.
  FirebaseFirestore? _tryGetDb() {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// Returns a FirebaseAuth instance, or null if Firebase is not initialized.
  FirebaseAuth? _tryGetAuth() {
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  String? get _userId => _tryGetAuth()?.currentUser?.uid;

  CollectionReference? get _userNotesRef {
    final uid = _userId;
    final db = _tryGetDb();
    if (uid == null || db == null) return null;
    return db.collection('users').doc(uid).collection('notes');
  }

  DocumentReference? get _userSettingsRef {
    final uid = _userId;
    final db = _tryGetDb();
    if (uid == null || db == null) return null;
    return db.collection('users').doc(uid).collection('settings').doc('vault');
  }

  // ── Vault PIN backup ────────────────────────────────────────────────────────

  /// Saves the vault PIN hash to Firestore so it survives app reinstalls and logouts.
  Future<void> saveVaultPinHash(String hash) async {
    final uid = _userId;
    final FirebaseFirestore? db = _tryGetDb();
    if (uid == null || db == null) return;

    // 1. Save directly to user document root
    try {
      await db.collection('users').doc(uid).set({
        'vault_pin_hash': hash,
        'vault_pin_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}

    // 2. Also save to settings/vault subcollection for compatibility
    final ref = _userSettingsRef;
    if (ref != null) {
      try {
        await ref.set({
          'pin_hash': hash,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  /// Retrieves the vault PIN hash from Firestore (used after login or reinstall).
  Future<String?> getVaultPinHash() async {
    final uid = _userId;
    final FirebaseFirestore? db = _tryGetDb();
    if (uid == null || db == null) return null;
    try {
      // 1. Check user document root
      final userDoc = await db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        final hash = data?['vault_pin_hash'] as String?;
        if (hash != null && hash.isNotEmpty) return hash;
      }

      // 2. Check settings/vault document
      final ref = _userSettingsRef;
      if (ref != null) {
        final doc = await ref.get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>?;
          final hash = data?['pin_hash'] as String?;
          if (hash != null && hash.isNotEmpty) return hash;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Removes the vault PIN hash from Firestore (only called on explicit "Forgot PIN / Reset Vault").
  Future<void> removeVaultPinHash() async {
    final uid = _userId;
    final FirebaseFirestore? db = _tryGetDb();
    if (uid == null || db == null) return;
    try {
      await db.collection('users').doc(uid).update({
        'vault_pin_hash': FieldValue.delete(),
      });
    } catch (_) {}

    final ref = _userSettingsRef;
    if (ref != null) {
      try {
        await ref.update({'pin_hash': FieldValue.delete()});
      } catch (_) {}
    }
  }

  // ── Note sync ───────────────────────────────────────────────────────────────

  /// Syncs a single note model to Cloud Firestore under users/{uid}/notes/{sNo}.
  /// Always called after any status change (vault/archive/normal) to keep
  /// Firestore up-to-date so reinstalls restore notes in the correct section.
  Future<void> syncNote(NoteModel note) async {
    final ref = _userNotesRef;
    if (ref == null || note.sNo == null) return;

    final data = note.toMap();
    // Overwrite with server timestamp for ordering/freshness queries on Firestore,
    // AND keep the ISO string under 'updated_at' so fromMap() can restore it.
    final nowIso = (note.updatedAt ?? DateTime.now()).toUtc().toIso8601String();
    data['updated_at'] = nowIso; // used by fromMap()
    data['updatedAt'] = FieldValue.serverTimestamp(); // Firestore native timestamp

    await ref.doc(note.sNo.toString()).set(data, SetOptions(merge: true));
  }

  /// Deletes a note from Cloud Firestore.
  Future<void> deleteNote(int sNo) async {
    final ref = _userNotesRef;
    if (ref == null) return;
    await ref.doc(sNo.toString()).delete();
  }

  /// Fetches ALL notes for current user from Cloud Firestore, regardless of
  /// status (normal / archive / vault). Used during reinstall sync so that
  /// notes keep their correct section instead of all appearing on Home.
  Future<List<NoteModel>> fetchRemoteNotes() async {
    final ref = _userNotesRef;
    if (ref == null) return [];

    final snapshot = await ref.get();
    return snapshot.docs.map((doc) {
      final raw = doc.data() as Map<String, dynamic>;
      final map = Map<String, dynamic>.from(raw);

      // Firestore stores the native Timestamp under 'updatedAt'; convert it
      // to the ISO string that NoteModel.fromMap() reads from 'updated_at'.
      if (!map.containsKey('updated_at') || (map['updated_at'] as String?)?.isEmpty != false) {
        final ts = map['updatedAt'];
        if (ts is Timestamp) {
          map['updated_at'] = ts.toDate().toUtc().toIso8601String();
        }
      }

      return NoteModel.fromMap(map);
    }).toList();
  }
}
