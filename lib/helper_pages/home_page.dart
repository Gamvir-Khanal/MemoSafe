import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'archive_page.dart';
import 'auth_service.dart';
import 'db_helper.dart';
import 'firestore_service.dart';
import 'note_card.dart';
import 'note_detail_page.dart';
import 'note_type.dart';
import 'pin_service.dart';
import 'theme_controller.dart';
import 'vault_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<NoteModel> _notes = [];
  bool _loading = true;

  bool _searching = false;
  final _searchController = TextEditingController();
  NoteSortOption _sort = NoteSortOption.newest;

  int _archiveCount = 0;
  int _vaultCount = 0;

  @override
  void initState() {
    super.initState();
    _loadNotes(showSpinner: true);
    _loadCounts();
    _syncFromCloud();
    _searchController.addListener(() => _loadNotes());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _syncFromCloud() async {
    try {
      await PinService.syncFromCloud();
      final remoteNotes = await FirestoreService.instance.fetchRemoteNotes();
      for (final note in remoteNotes) {
        // Use upsert so reinstalls don't create duplicate rows.
        await DBHelper.instance.upsertNote(note);
      }
      _loadNotes();
      _loadCounts();

      // Backfill: push every local note (all statuses) to Firestore so that
      // vault/archive statuses are always up-to-date in the cloud.
      final allLocal = await DBHelper.instance.getAllNotes();
      for (final n in allLocal) {
        if (n.sNo != null) {
          FirestoreService.instance.syncNote(n).catchError((_) {});
        }
      }
    } catch (_) {}
  }

  Future<void> _loadNotes({bool showSpinner = false}) async {
    if (showSpinner) setState(() => _loading = true);
    final notes = await DBHelper.instance.getNotes(
      query: _searchController.text,
      sort: _sort,
    );
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _deleteNote(int sNo) async {
    await DBHelper.instance.deleteNote(sNo);
    await FirestoreService.instance.deleteNote(sNo);
    _loadNotes();
  }

  Future<void> _loadCounts() async {
    final archive = await DBHelper.instance.countByStatus(NoteStatus.archive);
    final vault = await DBHelper.instance.countByStatus(NoteStatus.vault);
    if (!mounted) return;
    setState(() {
      _archiveCount = archive;
      _vaultCount = vault;
    });
  }

  Future<void> _togglePin(NoteModel note) async {
    await DBHelper.instance.updatePinned(note.sNo!, !note.isPinned);
    if (note.sNo != null) {
      await FirestoreService.instance.syncNote(
        note.copyWith(isPinned: !note.isPinned),
      );
    }
    _loadNotes();
  }

  Future<void> _openNote(NoteModel? note, {NoteType? forcedType}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteDetailPage(note: note, forcedType: forcedType),
      ),
    );
    _loadNotes();
    _loadCounts();

    final allNotes = await DBHelper.instance.getNotes();
    for (final n in allNotes) {
      if (n.sNo != null) {
        FirestoreService.instance.syncNote(n).catchError((_) {});
      }
    }
  }

  void _startSearch() => setState(() => _searching = true);

  void _exitSearch() {
    setState(() => _searching = false);
    _searchController.clear();
    _loadNotes(showSpinner: true);
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final updated = List<NoteModel>.from(_notes);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    setState(() => _notes = updated);
    final orderedSNos = updated
        .map((e) => e.sNo)
        .where((sNo) => sNo != null)
        .cast<int>()
        .toList();
    await DBHelper.instance.updateSortOrders(orderedSNos);
  }

  PopupMenuItem<NoteSortOption> _sortMenuItem(NoteSortOption option) {
    return PopupMenuItem(
      value: option,
      child: Row(
        children: [
          Icon(
            _sort == option
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 18,
            color: _sort == option
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          const SizedBox(width: 8),
          Text(option.label),
        ],
      ),
    );
  }

  void _showUserProfileModal(BuildContext context, User user) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.indigo.shade100,
                  backgroundImage:
                      (user.photoURL != null && user.photoURL!.isNotEmpty)
                          ? NetworkImage(user.photoURL!)
                          : null,
                  child: (user.photoURL == null || user.photoURL!.isEmpty)
                      ? Text(
                          (user.displayName ?? user.email ?? 'U')[0]
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 16),
                if (user.displayName != null && user.displayName!.isNotEmpty)
                  Text(
                    user.displayName!,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  user.email ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color
                        ?.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text(
                      'Sign Out',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await AuthService.instance.signOut();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Slide-up panel with Archive and Vault quick-access cards.
  void _showSectionsPanel() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Sections',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 16),
                // Archive card
                _SectionCard(
                  icon: Icons.archive_rounded,
                  label: 'Archive',
                  count: _archiveCount,
                  color: Colors.orange.shade600,
                  isDark: isDark,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ArchivePage()),
                    );
                    _loadNotes();
                    _loadCounts();
                  },
                ),
                const SizedBox(height: 12),
                // Vault card
                _SectionCard(
                  icon: Icons.lock_rounded,
                  label: 'Vault',
                  count: _vaultCount,
                  color: primary,
                  isDark: isDark,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const VaultGatePage()),
                    );
                    _loadNotes();
                    _loadCounts();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showNewNoteTypePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'New note',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
                for (final type in NoteType.values)
                  ListTile(
                    leading: Icon(type.icon),
                    title: Text(type.label),
                    onTap: () {
                      Navigator.of(context).pop();
                      _openNote(null, forcedType: type);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canReorder =
        _sort == NoteSortOption.manual && _searchController.text.trim().isEmpty;
    final user = AuthService.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        // ── Left: profile avatar ──────────────────────────────────────────
        leading: _searching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _exitSearch,
              )
            : Padding(
                padding: const EdgeInsets.all(8.0),
                child: GestureDetector(
                  onTap: () {
                    if (user != null) _showUserProfileModal(context, user);
                  },
                  child: CircleAvatar(
                    backgroundColor: Colors.indigo.shade100,
                    backgroundImage: (user?.photoURL != null &&
                            user!.photoURL!.isNotEmpty)
                        ? NetworkImage(user.photoURL!)
                        : null,
                    child: (user?.photoURL == null || user!.photoURL!.isEmpty)
                        ? Text(
                            (user?.displayName ?? user?.email ?? 'U')[0]
                                .toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
        // ── Centre: pill search bar ───────────────────────────────────────
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search notes...',
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              )
            : GestureDetector(
                onTap: _startSearch,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: theme.textTheme.bodyMedium?.color
                            ?.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Search notes...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodyMedium?.color
                              ?.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        // ── Right: sort + theme + sections menu ───────────────────────────
        actions: [
          if (_searching)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _exitSearch,
            )
          else ...[
            PopupMenuButton<NoteSortOption>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort',
              onSelected: (value) {
                setState(() => _sort = value);
                _loadNotes(showSpinner: true);
              },
              itemBuilder: (context) => [
                _sortMenuItem(NoteSortOption.newest),
                _sortMenuItem(NoteSortOption.oldest),
                _sortMenuItem(NoteSortOption.manual),
              ],
            ),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (context, mode, _) {
                final dark = mode == ThemeMode.dark;
                return IconButton(
                  icon: Icon(dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined),
                  tooltip: dark ? 'Light mode' : 'Dark mode',
                  onPressed: toggleTheme,
                );
              },
            ),
            // Sections button (Archive / Vault slide panel)
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.grid_view_rounded),
                  tooltip: 'Sections',
                  onPressed: _showSectionsPanel,
                ),
                if (_archiveCount + _vaultCount > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? Center(
                  child: Text(
                    _searching ? 'No matching notes.' : 'No notes yet.',
                    style: TextStyle(
                      color: theme.textTheme.bodyMedium?.color
                          ?.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : canReorder
                  ? ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: _notes.length,
                      onReorder: _handleReorder,
                      itemBuilder: (context, index) {
                        final note = _notes[index];
                        return Padding(
                          key: ValueKey(note.sNo ?? index),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: NoteCard(
                            note: note,
                            colorIndex: index,
                            onTap: () => _openNote(note),
                            onDelete: () => _deleteNote(note.sNo!),
                            onTogglePin: () => _togglePin(note),
                          ),
                        );
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: _notes.length,
                      itemBuilder: (context, index) {
                        final note = _notes[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: NoteCard(
                            note: note,
                            colorIndex: index,
                            onTap: () => _openNote(note),
                            onDelete: () => _deleteNote(note.sNo!),
                            onTogglePin: () => _togglePin(note),
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewNoteTypePicker,
        tooltip: 'New note',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── Reusable section card for the slide-up panel ───────────────────────────
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _SectionCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: 0.25),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (count > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  color: color.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}