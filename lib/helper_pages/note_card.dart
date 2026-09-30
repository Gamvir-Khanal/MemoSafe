import 'dart:convert';

import 'package:flutter/material.dart';

import 'checklist_item.dart';
import 'db_helper.dart';
import 'note_type.dart';

/// Rotating 5-color accent palette used for note cards' side border.
const List<Color> kAccentPalette = [
  Color(0xFFFCE38A), // warm yellow
  Color(0xFFB2F2BB), // mint green
  Color(0xFFAEC6FF), // soft blue
  Color(0xFFFFB4A2), // coral
  Color(0xFFE0BBE4), // lavender
];

Color accentColorFor(int index) =>
    kAccentPalette[index % kAccentPalette.length];

List<String> decodeJsonList(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded.map((e) => e.toString()).toList();
    return [];
  } catch (_) {
    // Legacy single-path notes created before the multi-item format.
    return [raw];
  }
}

/// Builds the small type-specific preview line shown under the title.
String previewTextFor(NoteModel note) {
  switch (note.mType) {
    case NoteType.text:
      return note.desc.trim().isEmpty ? 'No description' : note.desc.trim();
    case NoteType.images:
      final count = decodeJsonList(note.mImagePath).length;
      return count == 1 ? '1 photo' : '$count photos';
    case NoteType.audio:
      final count = decodeJsonList(note.mAudioPath).length;
      return count == 1 ? '1 recording' : '$count recordings';
    case NoteType.checklist:
      final items = ChecklistItem.decodeList(note.mChecklist);
      final done = items.where((e) => e.checked).length;
      return '$done/${items.length} done';
    case NoteType.drawing:
      return 'Sketch';
  }
}

/// A single simple, bordered note card used on Home/Archive/Vault.
/// The card surface follows the app theme; only a thin left-edge stripe
/// carries the rotating accent color, so the list stays calm and legible
/// instead of every card being a solid block of color.
class NoteCard extends StatelessWidget {
  final NoteModel note;
  final int colorIndex;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Optional — omit to hide the pin toggle entirely.
  final VoidCallback? onTogglePin;

  const NoteCard({
    super.key,
    required this.note,
    required this.colorIndex,
    required this.onTap,
    required this.onDelete,
    this.onTogglePin,
  });

  Future<void> _confirmDelete(BuildContext context) async {
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
    if (confirmed == true) onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColorFor(colorIndex);
    final titleColor = theme.textTheme.bodyLarge?.color;
    final subtleColor = theme.textTheme.bodySmall?.color?.withOpacity(0.7);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Row(
            children: [
              // Accent stripe — the only spot of color on the card.
              Container(
                width: 5,
                height: 56,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Icon(note.mType.icon, color: titleColor?.withOpacity(0.75)),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (note.isPinned) ...[
                            Icon(
                              Icons.push_pin,
                              size: 14,
                              color: Colors.amber[700],
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              note.title.trim().isEmpty
                                  ? '(Untitled)'
                                  : note.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: titleColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        previewTextFor(note),
                        style: TextStyle(color: subtleColor, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              if (onTogglePin != null)
                IconButton(
                  icon: Icon(
                    note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    color: note.isPinned ? Colors.amber[700] : subtleColor,
                  ),
                  tooltip: note.isPinned ? 'Unpin' : 'Pin to top',
                  onPressed: onTogglePin,
                ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: subtleColor),
                onPressed: () => _confirmDelete(context),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
