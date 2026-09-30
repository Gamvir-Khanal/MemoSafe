import 'package:flutter/material.dart';

enum NoteType { text, images, audio, checklist, drawing }

extension NoteTypeX on NoteType {
  String get label {
    switch (this) {
      case NoteType.text:
        return 'Text';
      case NoteType.images:
        return 'Images';
      case NoteType.audio:
        return 'Audio';
      case NoteType.checklist:
        return 'Checklist';
      case NoteType.drawing:
        return 'Drawing';
    }
  }

  IconData get icon {
    switch (this) {
      case NoteType.text:
        return Icons.notes_rounded;
      case NoteType.images:
        return Icons.photo_library_rounded;
      case NoteType.audio:
        return Icons.mic_rounded;
      case NoteType.checklist:
        return Icons.checklist_rounded;
      case NoteType.drawing:
        return Icons.draw_rounded;
    }
  }

  /// Value stored in the `mType` column.
  String get dbValue {
    switch (this) {
      case NoteType.text:
        return 'text';
      case NoteType.images:
        return 'images';
      case NoteType.audio:
        return 'audio';
      case NoteType.checklist:
        return 'checklist';
      case NoteType.drawing:
        return 'drawing';
    }
  }

  static NoteType fromDb(String? value) {
    switch (value) {
      case 'images':
        return NoteType.images;
      case 'audio':
        return NoteType.audio;
      case 'checklist':
        return NoteType.checklist;
      case 'drawing':
        return NoteType.drawing;
      case 'text':
      default:
        return NoteType.text;
    }
  }
}

/// Status of a note: where it currently lives.
enum NoteStatus { normal, archive, vault }

extension NoteStatusX on NoteStatus {
  String get dbValue {
    switch (this) {
      case NoteStatus.normal:
        return 'normal';
      case NoteStatus.archive:
        return 'archive';
      case NoteStatus.vault:
        return 'vault';
    }
  }

  static NoteStatus fromDb(String? value) {
    switch (value) {
      case 'archive':
        return NoteStatus.archive;
      case 'vault':
        return NoteStatus.vault;
      case 'normal':
      default:
        return NoteStatus.normal;
    }
  }
}

/// How the Home note list should be ordered.
enum NoteSortOption { newest, oldest, manual }

extension NoteSortOptionX on NoteSortOption {
  String get label {
    switch (this) {
      case NoteSortOption.newest:
        return 'Newest first';
      case NoteSortOption.oldest:
        return 'Oldest first';
      case NoteSortOption.manual:
        return 'Custom order (drag to reorder)';
    }
  }
}
