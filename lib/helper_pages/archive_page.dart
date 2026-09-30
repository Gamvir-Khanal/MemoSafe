import 'package:flutter/material.dart';

import 'db_helper.dart';
import 'firestore_service.dart';
import 'note_card.dart';
import 'note_detail_page.dart';
import 'note_type.dart';

class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  List<NoteModel> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final notes = await DBHelper.instance.getNotesByStatus(NoteStatus.archive);
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _deleteNote(int sNo) async {
    await DBHelper.instance.deleteNote(sNo);
    await FirestoreService.instance.deleteNote(sNo);
    _load();
  }

  Future<void> _togglePin(NoteModel note) async {
    await DBHelper.instance.updatePinned(note.sNo!, !note.isPinned);
    _load();
  }

  Future<void> _openNote(NoteModel note) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => NoteDetailPage(note: note)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Archive')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
          ? const Center(child: Text('Archive is empty.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _notes.length,
                itemBuilder: (context, index) {
                  final note = _notes[index];
                  return NoteCard(
                    note: note,
                    colorIndex: index,
                    onTap: () => _openNote(note),
                    onDelete: () => _deleteNote(note.sNo!),
                    onTogglePin: () => _togglePin(note),
                  );
                },
              ),
            ),
    );
  }
}
