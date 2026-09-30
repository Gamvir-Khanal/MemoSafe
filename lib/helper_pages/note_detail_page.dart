import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_clip.dart';
import 'checklist_item.dart';
import 'db_helper.dart';
import 'drawing_canvas.dart';
import 'firestore_service.dart';
import 'image_viewer_page.dart';
import 'note_type.dart';
import 'security_service.dart';

class NoteDetailPage extends StatefulWidget {
  /// Existing note to edit, or null when creating a new note.
  final NoteModel? note;

  /// Required when [note] is null — locks the editor to this type.
  final NoteType? forcedType;

  const NoteDetailPage({super.key, this.note, this.forcedType});

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  late final NoteType _type;
  late NoteStatus _status;
  late bool _isPinned;

  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  List<String> _imagePaths = [];
  List<AudioClip> _audioClips = [];
  List<ChecklistItem> _checklistItems = [];
  final List<FocusNode> _checklistFocusNodes = [];

  List<DrawStroke> _strokes = [];
  Color _sketchColor = Colors.black;
  double _sketchWidth = 4.0;
  final _sketchPadKey = GlobalKey<SketchPadState>();

  /// Cache of probed clip durations, keyed by file path, so a duration
  /// only ever needs to be read from disk once per clip.
  final Map<String, Duration?> _audioDurations = {};

  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();

  bool _isRecording = false;
  String? _playingPath;

  bool get _isEditing => widget.note != null;

  // ── Dirty-state tracking ────────────────────────────────────────────────────
  // Snapshot of original values captured once in initState. Any change from
  // these marks the note as "dirty" so the unsaved-changes guard fires.
  String _origTitle = '';
  String _origDesc = '';
  String _origChecklist = '';
  String _origImages = '';
  String _origAudio = '';
  String _origStrokes = '';

  /// Timestamp of the last successful save — shown at the bottom of the page.
  DateTime? _updatedAt;

  bool get _isDirty {
    if (_titleController.text.trim() != _origTitle) return true;
    if (_descController.text.trim() != _origDesc) return true;
    if (ChecklistItem.encodeList(_checklistItems) != _origChecklist) return true;
    if (jsonEncode(_imagePaths) != _origImages) return true;
    if (AudioClip.encodeList(_audioClips) != _origAudio) return true;
    if (DrawStroke.encodeList(_strokes) != _origStrokes) return true;
    return false;
  }

  void _markDirty() => setState(() {}); // Triggers _isDirty getter re-eval.

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _type = note?.mType ?? widget.forcedType ?? NoteType.text;
    _status = note?.mStatus ?? NoteStatus.normal;
    _isPinned = note?.isPinned ?? false;
    _updatedAt = note?.updatedAt;

    if (note != null) {
      _titleController.text = note.title;
      _descController.text = note.desc;
      _imagePaths = _decodeList(note.mImagePath);
      _audioClips = AudioClip.decodeList(note.mAudioPath);
      for (var i = 0; i < _audioClips.length; i++) {
        if (_audioClips[i].name.trim().isEmpty) {
          _audioClips[i].name = 'Recording ${i + 1}';
        }
      }
      _checklistItems = ChecklistItem.decodeList(note.mChecklist);
      _checklistFocusNodes.addAll(
        List.generate(_checklistItems.length, (_) => FocusNode()),
      );
      _strokes = DrawStroke.decodeList(note.mDrawingPath);
    }

    // Capture originals AFTER populating from the note so that the first
    // open of an existing note does NOT appear dirty.
    _origTitle = _titleController.text.trim();
    _origDesc = _descController.text.trim();
    _origChecklist = ChecklistItem.encodeList(_checklistItems);
    _origImages = jsonEncode(_imagePaths);
    _origAudio = AudioClip.encodeList(_audioClips);
    _origStrokes = DrawStroke.encodeList(_strokes);

    // Listen to text fields so dirty state re-evaluates on every keystroke.
    _titleController.addListener(_markDirty);
    _descController.addListener(_markDirty);

    if (_type == NoteType.audio) _probeMissingDurations();
    if (_type == NoteType.drawing) _loadCustomColors();
  }

  /// Key under which the user's custom (non-palette) sketch colors are
  /// persisted, shared across every note/session rather than reset each
  /// time this page is closed and reopened.
  static const _customColorsPrefKey = 'sketch_custom_colors';

  /// Restores previously-saved custom colors so they keep showing up in
  /// the swatch row after leaving and re-entering a drawing note.
  Future<void> _loadCustomColors() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_customColorsPrefKey) ?? [];
    if (saved.isEmpty || !mounted) return;
    setState(() {
      _customColors
        ..clear()
        ..addAll(saved.map((s) => Color(int.parse(s))));
    });
  }

  /// Persists the current custom color list so it survives closing the
  /// note and reopening it (or opening a different drawing note) later.
  Future<void> _saveCustomColors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _customColorsPrefKey,
      _customColors.map((c) => c.value.toString()).toList(),
    );
  }

  /// Reads the length of every audio clip that doesn't already carry a
  /// known [AudioClip.durationMs] — new clips get theirs set right away
  /// when recorded/picked, so this mainly covers notes saved before the
  /// duration badge existed.
  Future<void> _probeMissingDurations() async {
    for (final clip in _audioClips) {
      if (clip.durationMs != null) {
        _audioDurations[clip.path] = Duration(milliseconds: clip.durationMs!);
        continue;
      }
      final duration = await _probeDuration(clip.path);
      if (duration != null) clip.durationMs = duration.inMilliseconds;
      if (!mounted) return;
      setState(() => _audioDurations[clip.path] = duration);
    }
  }

  /// Loads a clip just long enough to read its length, without playing it.
  Future<Duration?> _probeDuration(String path) async {
    final probe = AudioPlayer();
    try {
      final bytes = await SecurityService.instance.decryptFile(File(path));
      await probe.setSourceBytes(bytes);
      return await probe.getDuration();
    } catch (_) {
      return null;
    } finally {
      await probe.dispose();
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _titleController.removeListener(_markDirty);
    _descController.removeListener(_markDirty);
    _titleController.dispose();
    _descController.dispose();
    _recorder.dispose();
    _player.dispose();
    for (final node in _checklistFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  List<String> _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
      return [];
    } catch (_) {
      // Legacy single-path note from before the multi-item format change.
      return [raw];
    }
  }

  // ---------------- Save / Delete ----------------

  Future<int> _persist() async {
    final now = DateTime.now();
    final note = NoteModel(
      sNo: widget.note?.sNo,
      title: _titleController.text.trim(),
      desc: _type == NoteType.text ? _descController.text.trim() : '',
      mImagePath: _type == NoteType.images ? jsonEncode(_imagePaths) : null,
      mAudioPath: _type == NoteType.audio
          ? AudioClip.encodeList(_audioClips)
          : null,
      mChecklist: _type == NoteType.checklist
          ? ChecklistItem.encodeList(_checklistItems)
          : null,
      mDrawingPath: _type == NoteType.drawing
          ? DrawStroke.encodeList(_strokes)
          : null,
      mType: _type,
      mStatus: _status,
      isPinned: _isPinned,
      updatedAt: now,
    );

    late int sNo;
    if (_isEditing) {
      await DBHelper.instance.updateNote(note);
      sNo = note.sNo!;
    } else {
      sNo = await DBHelper.instance.addNote(note);
    }
    setState(() => _updatedAt = now);
    return sNo;
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      if (_type == NoteType.text && _descController.text.trim().isNotEmpty) {
        final firstLine = _descController.text.trim().split('\n').first.trim();
        _titleController.text =
            firstLine.length > 30 ? '${firstLine.substring(0, 30)}...' : firstLine;
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please add a title.')));
        return;
      }
    }
    final sNo = await _persist();
    // Sync to Firestore and reset dirty baseline.
    _syncToFirestore(sNo);
    _resetDirtyBaseline();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Note saved'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  /// Resets the dirty-tracking baseline to the current content so that
  /// immediately after saving the note is no longer considered dirty.
  void _resetDirtyBaseline() {
    _origTitle = _titleController.text.trim();
    _origDesc = _descController.text.trim();
    _origChecklist = ChecklistItem.encodeList(_checklistItems);
    _origImages = jsonEncode(_imagePaths);
    _origAudio = AudioClip.encodeList(_audioClips);
    _origStrokes = DrawStroke.encodeList(_strokes);
  }

  void _syncToFirestore(int sNo) {
    final note = NoteModel(
      sNo: sNo,
      title: _titleController.text.trim(),
      desc: _type == NoteType.text ? _descController.text.trim() : '',
      mImagePath: _type == NoteType.images ? jsonEncode(_imagePaths) : null,
      mAudioPath:
          _type == NoteType.audio ? AudioClip.encodeList(_audioClips) : null,
      mChecklist: _type == NoteType.checklist
          ? ChecklistItem.encodeList(_checklistItems)
          : null,
      mDrawingPath:
          _type == NoteType.drawing ? DrawStroke.encodeList(_strokes) : null,
      mType: _type,
      mStatus: _status,
      isPinned: _isPinned,
    );
    FirestoreService.instance.syncNote(note).catchError((_) {});
  }

  // ── Unsaved-changes guard ────────────────────────────────────────────────────

  /// Shows the premium "Unsaved changes" bottom-sheet and handles the three
  /// outcomes: Save, Discard, or Cancel (stay on page).
  ///
  /// Returns `true` if the caller should now pop the page, `false` if not.
  Future<bool> _handleUnsavedChanges() async {
    final result = await showModalBottomSheet<UnsavedAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => UnsavedChangesSheet(isNewNote: !_isEditing),
    );

    if (result == null || result == UnsavedAction.cancel) return false;

    if (result == UnsavedAction.save) {
      if (_titleController.text.trim().isEmpty) {
        if (_type == NoteType.text && _descController.text.trim().isNotEmpty) {
          final firstLine =
              _descController.text.trim().split('\n').first.trim();
          _titleController.text = firstLine.length > 30
              ? '${firstLine.substring(0, 30)}...'
              : firstLine;
        } else {
          _titleController.text = 'Untitled ${_type.label}';
        }
      }
      final sNo = await _persist();
      _syncToFirestore(sNo);
      _resetDirtyBaseline();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note saved'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return true; // Pop after save.
    }

    // Discard — pop without saving.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Changes discarded'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    return true;
  }

  /// Central back-navigation handler. Called by both the AppBar back button
  /// and the OS/gesture back via [PopScope].
  Future<void> _onBack() async {
    if (!_isDirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final shouldPop = await _handleUnsavedChanges();
    if (shouldPop && mounted) Navigator.of(context).pop();
  }

  /// Flips the pinned flag. For an existing note this saves immediately
  /// (like the archive/vault move actions) so the change sticks even if
  /// the user backs out without hitting the main save button; for a new,
  /// unsaved note it just updates local state until the note is saved.
  Future<void> _togglePin() async {
    setState(() => _isPinned = !_isPinned);
    if (_isEditing) await _persist();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && widget.note?.sNo != null) {
      await DBHelper.instance.deleteNote(widget.note!.sNo!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ---------------- Move to Archive / Vault ----------------

  Future<void> _moveTo(NoteStatus target) async {
    setState(() => _status = target);
    final sNo = await _persist();
    // Immediately sync the updated status to Firestore so reinstalls restore
    // this note in the correct section (vault / archive / normal).
    final synced = NoteModel(
      sNo: sNo,
      title: _titleController.text.trim(),
      desc: _type == NoteType.text ? _descController.text.trim() : '',
      mImagePath: _type == NoteType.images ? jsonEncode(_imagePaths) : null,
      mAudioPath:
          _type == NoteType.audio ? AudioClip.encodeList(_audioClips) : null,
      mChecklist: _type == NoteType.checklist
          ? ChecklistItem.encodeList(_checklistItems)
          : null,
      mDrawingPath:
          _type == NoteType.drawing ? DrawStroke.encodeList(_strokes) : null,
      mType: _type,
      mStatus: target,
      isPinned: _isPinned,
    );
    FirestoreService.instance.syncNote(synced).catchError((_) {});
    if (!mounted) return;
    final label = switch (target) {
      NoteStatus.archive => 'Archive',
      NoteStatus.vault => 'Vault',
      NoteStatus.normal => 'Notes',
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Note moved to $label.')));
    Navigator.of(context).pop();
  }

  List<PopupMenuEntry<NoteStatus>> _moveMenuItems() {
    final items = <PopupMenuEntry<NoteStatus>>[];
    if (_status != NoteStatus.normal) {
      items.add(
        const PopupMenuItem(
          value: NoteStatus.normal,
          child: ListTile(
            leading: Icon(Icons.unarchive_outlined),
            title: Text('Restore to Notes'),
          ),
        ),
      );
    }
    if (_status != NoteStatus.archive) {
      items.add(
        const PopupMenuItem(
          value: NoteStatus.archive,
          child: ListTile(
            leading: Icon(Icons.archive_outlined),
            title: Text('Move to Archive'),
          ),
        ),
      );
    }
    if (_status != NoteStatus.vault) {
      items.add(
        const PopupMenuItem(
          value: NoteStatus.vault,
          child: ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Move to Vault'),
          ),
        ),
      );
    }
    return items;
  }

  // ---------------- Images ----------------

  Future<String> _appDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty) return;
    final dir = await _appDir();
    final newPaths = <String>[];
    for (final file in picked) {
      final ext = file.path.split('.').last;
      final destPath =
          '$dir/img_${DateTime.now().microsecondsSinceEpoch}_${newPaths.length}.$ext';
      await SecurityService.instance.encryptFile(
        File(file.path),
        targetFile: File(destPath),
      );
      newPaths.add(destPath);
    }
    setState(() => _imagePaths.addAll(newPaths));
  }

  void _removeImage(int index) {
    setState(() => _imagePaths.removeAt(index));
  }

  void _viewImage(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ImageViewerPage(imagePaths: _imagePaths, initialIndex: index),
      ),
    );
  }

  Widget _buildImagesBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: OutlinedButton.icon(
            onPressed: _pickImages,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add photos'),
          ),
        ),
        Expanded(
          child: _imagePaths.isEmpty
              ? const Center(child: Text('No photos yet.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _imagePaths.length,
                  itemBuilder: (context, index) {
                    final path = _imagePaths[index];
                    return GestureDetector(
                      onTap: () => _viewImage(index),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: FutureBuilder<Uint8List>(
                              future: SecurityService.instance.decryptFile(File(path)),
                              builder: (context, snapshot) {
                                if (snapshot.hasData) {
                                  return Image.memory(
                                    snapshot.data!,
                                    fit: BoxFit.cover,
                                  );
                                }
                                return Container(
                                  color: Colors.black12,
                                  child: const Center(
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                );
                              },
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _removeImage(index),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------------- Audio ----------------

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      if (path != null) {
        await SecurityService.instance.encryptFile(File(path));
      }
      setState(() {
        _isRecording = false;
        if (path != null) {
          _audioClips.add(
            AudioClip(path: path, name: 'Recording ${_audioClips.length + 1}'),
          );
        }
      });
      if (path != null) {
        final duration = await _probeDuration(path);
        if (duration != null) {
          final clip = _audioClips.firstWhere((c) => c.path == path);
          clip.durationMs = duration.inMilliseconds;
        }
        if (mounted) setState(() => _audioDurations[path] = duration);
      }
    } else {
      if (await _recorder.hasPermission()) {
        final dir = await _appDir();
        final path = '$dir/audio_${DateTime.now().microsecondsSinceEpoch}.m4a';
        await _recorder.start(const RecordConfig(), path: path);
        setState(() => _isRecording = true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required.')),
        );
      }
    }
  }

  Future<void> _togglePlay(String path) async {
    if (_playingPath == path) {
      await _player.stop();
      setState(() => _playingPath = null);
    } else {
      await _player.stop();
      final bytes = await SecurityService.instance.decryptFile(File(path));
      await _player.play(BytesSource(bytes));
      setState(() => _playingPath = path);
      _player.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _playingPath = null);
      });
    }
  }

  Future<void> _pickAudioFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg'],
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final dir = await _appDir();
      final newClips = <AudioClip>[];
      for (final file in result.files) {
        final ext = (file.extension != null && file.extension!.isNotEmpty)
            ? file.extension!
            : 'mp3';
        final destPath =
            '$dir/audio_${DateTime.now().microsecondsSinceEpoch}_${newClips.length}.$ext';

        if (file.path != null) {
          await SecurityService.instance.encryptFile(
            File(file.path!),
            targetFile: File(destPath),
          );
        } else if (file.bytes != null) {
          final encBytes = await SecurityService.instance.encryptBytes(file.bytes!);
          await File(destPath).writeAsBytes(encBytes);
        } else {
          continue;
        }

        final displayName = file.name.contains('.')
            ? file.name.substring(0, file.name.lastIndexOf('.'))
            : file.name;
        newClips.add(
          AudioClip(
            path: destPath,
            name: displayName.trim().isEmpty
                ? 'Recording ${_audioClips.length + newClips.length + 1}'
                : displayName,
          ),
        );
      }

      if (newClips.isNotEmpty) {
        setState(() => _audioClips.addAll(newClips));
        for (final clip in newClips) {
          final duration = await _probeDuration(clip.path);
          if (duration != null) clip.durationMs = duration.inMilliseconds;
          if (!mounted) return;
          setState(() => _audioDurations[clip.path] = duration);
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the selected file(s).')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add audio file: $e')));
      }
    }
  }

  Future<void> _removeAudio(int index) async {
    final clip = _audioClips[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recording?'),
        content: Text(
          'Are you sure you want to delete "${clip.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (_playingPath == clip.path) {
      await _player.stop();
      _playingPath = null;
    }
    // Best-effort cleanup of the copied file on disk.
    try {
      final file = File(clip.path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Ignore — worst case an orphaned file is left in app storage.
    }
    _audioDurations.remove(clip.path);
    if (mounted) setState(() => _audioClips.removeAt(index));
  }

  Future<void> _renameAudioClip(int index) async {
    final controller = TextEditingController(text: _audioClips[index].name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename recording'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Meeting notes'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      setState(() => _audioClips[index].name = newName);
    }
  }

  Widget _buildAudioBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              FloatingActionButton(
                heroTag: 'recordAudioFab',
                tooltip: _isRecording ? 'Stop recording' : 'Record audio',
                onPressed: _toggleRecording,
                backgroundColor: _isRecording
                    ? Theme.of(context).colorScheme.errorContainer
                    : null,
                child: Icon(_isRecording ? Icons.stop : Icons.mic),
              ),
              const SizedBox(width: 16),
              FloatingActionButton(
                heroTag: 'pickAudioFab',
                tooltip: 'Add audio file from device',
                onPressed: _pickAudioFiles,
                child: const Icon(Icons.upload_file_outlined),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _isRecording ? 'Recording…' : 'Record or add a clip',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _audioClips.isEmpty
              ? const Center(child: Text('No recordings yet.'))
              : ListView.builder(
                  itemCount: _audioClips.length,
                  itemBuilder: (context, index) {
                    final clip = _audioClips[index];
                    final isPlaying = _playingPath == clip.path;
                    return ListTile(
                      leading: IconButton(
                        icon: Icon(
                          isPlaying ? Icons.pause_circle : Icons.play_circle,
                        ),
                        onPressed: () => _togglePlay(clip.path),
                      ),
                      title: Text(clip.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_audioDurations[clip.path] != null)
                            Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _formatDuration(_audioDurations[clip.path]!),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Rename',
                            onPressed: () => _renameAudioClip(index),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete',
                            onPressed: () => _removeAudio(index),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------------- Checklist ----------------

  /// Inserts a new empty item right after [afterIndex] (or at the very
  /// start if -1) and immediately focuses it, so both the "Add item"
  /// button and pressing Enter/Done on the keyboard jump straight into
  /// typing the next item.
  void _insertChecklistItemAfter(int afterIndex) {
    final node = FocusNode();
    final insertAt = afterIndex + 1;
    setState(() {
      _checklistItems.insert(insertAt, ChecklistItem(text: ''));
      _checklistFocusNodes.insert(insertAt, node);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).requestFocus(node);
    });
  }

  void _addChecklistItem() {
    _insertChecklistItemAfter(_checklistItems.length - 1);
  }

  void _removeChecklistItem(int index) {
    _checklistFocusNodes[index].dispose();
    setState(() {
      _checklistItems.removeAt(index);
      _checklistFocusNodes.removeAt(index);
    });
  }

  Widget _buildChecklistBody() {
    return Column(
      children: [
        Expanded(
          child: _checklistItems.isEmpty
              ? const Center(child: Text('No items yet.'))
              : ListView.builder(
                  itemCount: _checklistItems.length,
                  itemBuilder: (context, index) {
                    final item = _checklistItems[index];
                    return ListTile(
                      key: ObjectKey(_checklistFocusNodes[index]),
                      leading: Checkbox(
                        value: item.checked,
                        onChanged: (v) =>
                            setState(() => item.checked = v ?? false),
                      ),
                      title: TextFormField(
                        initialValue: item.text,
                        focusNode: _checklistFocusNodes[index],
                        textInputAction: TextInputAction.next,
                        style: TextStyle(
                          decoration: item.checked
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          color: item.checked
                              ? Theme.of(context).disabledColor
                              : (Theme.of(context).textTheme.bodyLarge?.color ??
                                        Colors.black)
                                    .withOpacity(
                                      item.text.trim().isEmpty ? 0.45 : 1.0,
                                    ),
                        ),
                        decoration: InputDecoration(
                          hintText: 'List item',
                          hintStyle: TextStyle(
                            color: Theme.of(context).hintColor.withOpacity(0.5),
                          ),
                          border: InputBorder.none,
                        ),
                        onChanged: (v) => setState(() => item.text = v),
                        onFieldSubmitted: (_) =>
                            _insertChecklistItemAfter(index),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _removeChecklistItem(index),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(
            onPressed: _addChecklistItem,
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        ),
      ],
    );
  }

  // ---------------- Drawing ----------------

  static const List<Color> _sketchPalette = [
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
  ];

  /// Custom colors the user has picked this session, shown after the
  /// fixed palette so they're easy to reuse without reopening the picker.
  final List<Color> _customColors = [];

  Widget _swatch(Color color, {VoidCallback? onDelete}) {
    final selected = _sketchColor == color;
    // A visible border on every swatch — without it, black (or any color
    // close to the app's own dark-mode background) can be nearly
    // invisible against the surrounding surface.
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4),
      child: GestureDetector(
        onTap: () => setState(() => _sketchColor = color),
        onLongPress: onDelete,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.6),
              width: 1.5,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  size: 16,
                  color: color.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }

  /// Removes a user-added custom color. If it was the active drawing
  /// color, falls back to black — one of the fixed base colors that's
  /// always present — rather than leaving [_sketchColor] pointing at a
  /// color that no longer appears anywhere in the row.
  void _removeCustomColor(Color color) {
    setState(() {
      _customColors.remove(color);
      if (_sketchColor == color) _sketchColor = Colors.black;
    });
    _saveCustomColors();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Custom color removed.')));
  }

  Widget _addCustomColorButton() {
    return GestureDetector(
      onTap: _pickCustomColor,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.6),
            width: 1.5,
          ),
        ),
        child: Icon(
          Icons.add,
          size: 18,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
    );
  }

  /// Opens a simple RGB-slider + hex-entry dialog so the user isn't
  /// limited to the fixed palette. The chosen color is added to
  /// [_customColors] so it stays available in the row afterward.
  Future<void> _pickCustomColor() async {
    Color working = _sketchColor;
    final hexController = TextEditingController(
      text: working.value.toRadixString(16).substring(2).toUpperCase(),
    );

    final picked = await showDialog<Color>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void updateFromRgb() {
              hexController.text = working.value
                  .toRadixString(16)
                  .substring(2)
                  .toUpperCase();
            }

            void updateFromHex(String hex) {
              final cleaned = hex.replaceAll('#', '').trim();
              if (cleaned.length == 6) {
                final parsed = int.tryParse(cleaned, radix: 16);
                if (parsed != null) {
                  setDialogState(() => working = Color(0xFF000000 | parsed));
                }
              }
            }

            Widget rgbSlider(
              String label,
              int value,
              ValueChanged<int> onChanged,
            ) {
              return Row(
                children: [
                  SizedBox(width: 16, child: Text(label)),
                  Expanded(
                    child: Slider(
                      value: value.toDouble(),
                      min: 0,
                      max: 255,
                      divisions: 255,
                      onChanged: (v) => onChanged(v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text('$value', textAlign: TextAlign.end),
                  ),
                ],
              );
            }

            return AlertDialog(
              title: const Text('Custom color'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    height: 48,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: working,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  rgbSlider('R', working.red, (v) {
                    setDialogState(() => working = working.withRed(v));
                    updateFromRgb();
                  }),
                  rgbSlider('G', working.green, (v) {
                    setDialogState(() => working = working.withGreen(v));
                    updateFromRgb();
                  }),
                  rgbSlider('B', working.blue, (v) {
                    setDialogState(() => working = working.withBlue(v));
                    updateFromRgb();
                  }),
                  TextField(
                    controller: hexController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      prefixText: '#',
                      labelText: 'Hex',
                    ),
                    onSubmitted: updateFromHex,
                    onChanged: updateFromHex,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(working),
                  child: const Text('Use color'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != null) {
      setState(() {
        _sketchColor = picked;
        if (!_customColors.contains(picked)) _customColors.add(picked);
      });
      _saveCustomColors();
    }
  }

  Widget _buildDrawingBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final color in _sketchPalette) _swatch(color),
                      for (final color in _customColors)
                        _swatch(
                          color,
                          onDelete: () => _removeCustomColor(color),
                        ),
                      _addCustomColorButton(),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Undo last stroke',
                icon: const Icon(Icons.undo),
                // Deactivates the button action if there's nothing to undo
                onPressed: _sketchPadKey.currentState?.canUndo == true
                    ? () {
                        _sketchPadKey.currentState?.undo();
                        setState(() {});
                      }
                    : null,
              ),
              IconButton(
                tooltip: 'Redo last stroke',
                icon: const Icon(Icons.redo),
                // Deactivates the button action if the redo stack is empty
                onPressed: _sketchPadKey.currentState?.canRedo == true
                    ? () {
                        _sketchPadKey.currentState?.redo();
                        setState(() {});
                      }
                    : null,
              ),
              IconButton(
                tooltip: 'Clear sketch',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () => _sketchPadKey.currentState?.clear(),
              ),
            ],
          ),
        ),
        if (_customColors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Long-press a custom color to delete it.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).hintColor,
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.line_weight, size: 18),
              Expanded(
                child: Slider(
                  value: _sketchWidth,
                  min: 1,
                  max: 16,
                  onChanged: (v) => setState(() => _sketchWidth = v),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SketchPad(
              key: _sketchPadKey,
              initialStrokes: _strokes,
              color: _sketchColor,
              strokeWidth: _sketchWidth,
              onChanged: (strokes) {
                setState(() {
                  _strokes = strokes;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── Last-updated timestamp bar ───────────────────────────────────────────────

  /// Returns a human-readable label like "Today, 2:35 PM" or "Sep 28, 10:00 AM".
  String _formatUpdatedAt(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final noteDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(noteDay).inDays;

    final timeStr =
        '${dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour)}:'
        '${dt.minute.toString().padLeft(2, '0')} '
        '${dt.hour >= 12 ? 'PM' : 'AM'}';

    if (diff == 0) return 'Today, $timeStr';
    if (diff == 1) return 'Yesterday, $timeStr';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, $timeStr';
  }

  Widget _buildUpdatedAtBar() {
    final ts = _updatedAt;
    if (ts == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(
              Icons.history_rounded,
              size: 13,
              color: theme.hintColor.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Text(
              'Edited ${_formatUpdatedAt(ts)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.hintColor.withValues(alpha: 0.7),
                fontSize: 11,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Build ----------------

  Widget _buildTypeBody() {
    switch (_type) {
      case NoteType.text:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _descController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              hintText: 'Write your note...',
              border: InputBorder.none,
            ),
          ),
        );
      case NoteType.images:
        return _buildImagesBody();
      case NoteType.audio:
        return _buildAudioBody();
      case NoteType.checklist:
        return _buildChecklistBody();
      case NoteType.drawing:
        return _buildDrawingBody();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Never let the system pop automatically — we handle it ourselves so
      // we can intercept the back gesture when there are unsaved changes.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return; // Already popped (shouldn't happen with canPop: false).
        await _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          // Custom back button so it runs the same guard as the OS back gesture.
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _onBack,
          ),
          title: Text(_isEditing ? 'Edit ${_type.label}' : 'New ${_type.label}'),
          actions: [
            IconButton(
              icon: Icon(_isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              color: _isPinned ? Colors.amber[700] : null,
              tooltip: _isPinned ? 'Unpin' : 'Pin to top',
              onPressed: _togglePin,
            ),
            if (_isEditing)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
            IconButton(icon: const Icon(Icons.check), onPressed: _save),
          ],
        ),
      body: Padding(
        padding: EdgeInsets.only(bottom: _isEditing ? 40 : 0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Title',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (_status != NoteStatus.normal)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(switch (_status) {
                        NoteStatus.archive => 'In Archive',
                        NoteStatus.vault => 'In Vault',
                        NoteStatus.normal => '',
                      }, style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildTypeBody()),
          ],
        ),
      ),
      bottomNavigationBar: _updatedAt != null ? _buildUpdatedAtBar() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: _isEditing
          ? PopupMenuButton<NoteStatus>(
              tooltip: 'Move note',
              itemBuilder: (context) => _moveMenuItems(),
              onSelected: _moveTo,
              offset: const Offset(0, -160),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 10,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.drive_file_move_outline,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            )
          : null,
      ),
    );
  }
}

enum UnsavedAction {
  save,
  discard,
  cancel,
}

class UnsavedChangesSheet extends StatelessWidget {
  final bool isNewNote;

  const UnsavedChangesSheet({super.key, required this.isNewNote});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
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
                // Header with icon + title + description
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.amber,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Unsaved Changes',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isNewNote
                                ? 'You have unsaved changes in this new note. Do you want to save it before leaving?'
                                : 'You have unsaved modifications. Do you want to save your changes before leaving?',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withValues(alpha: 0.7),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Save button
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: const Text(
                    'Save & Exit',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  onPressed: () => Navigator.of(context).pop(UnsavedAction.save),
                ),
                const SizedBox(height: 10),
                // Don't save (Discard) button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(
                      color: theme.colorScheme.error.withValues(alpha: 0.4),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  label: const Text(
                    "Don't Save",
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  onPressed: () =>
                      Navigator.of(context).pop(UnsavedAction.discard),
                ),
                const SizedBox(height: 8),
                // Keep editing (Cancel) button
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Keep Editing',
                    style: TextStyle(
                      color: theme.textTheme.bodyMedium?.color
                          ?.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () =>
                      Navigator.of(context).pop(UnsavedAction.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

