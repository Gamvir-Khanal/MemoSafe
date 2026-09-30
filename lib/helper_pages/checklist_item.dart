import 'dart:convert';

class ChecklistItem {
  String text;
  bool checked;

  ChecklistItem({required this.text, this.checked = false});

  Map<String, dynamic> toJson() => {'text': text, 'checked': checked};

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
    text: json['text'] ?? '',
    checked: json['checked'] ?? false,
  );

  static String encodeList(List<ChecklistItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<ChecklistItem> decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
