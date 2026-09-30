import 'dart:convert';

class AudioClip {
  String path;
  String name;

  /// Clip length in milliseconds, once known. Null until probed (older
  /// clips saved before this field existed, or a probe that failed).
  int? durationMs;

  AudioClip({required this.path, required this.name, this.durationMs});

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    if (durationMs != null) 'durationMs': durationMs,
  };

  factory AudioClip.fromJson(Map<String, dynamic> json) => AudioClip(
    path: json['path']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    durationMs: json['durationMs'] is int
        ? json['durationMs'] as int
        : int.tryParse(json['durationMs']?.toString() ?? ''),
  );

  static String encodeList(List<AudioClip> clips) =>
      jsonEncode(clips.map((e) => e.toJson()).toList());

  /// Decodes the `mAudioPath` column. Handles both the current format
  /// (a JSON list of `{path, name}` objects) and the older format used
  /// before naming was added (a JSON list of plain path strings), so
  /// existing notes keep working.
  static List<AudioClip> decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final clips = <AudioClip>[];
        for (final entry in decoded) {
          if (entry is Map) {
            clips.add(AudioClip.fromJson(Map<String, dynamic>.from(entry)));
          } else {
            // Legacy: plain path string, no name yet.
            clips.add(AudioClip(path: entry.toString(), name: ''));
          }
        }
        return clips;
      }
      return [];
    } catch (_) {
      // Even older legacy format: a single raw path, not JSON at all.
      return [AudioClip(path: raw, name: '')];
    }
  }
}
