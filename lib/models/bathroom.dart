/// Shared facility data. Creator attribution does not imply exclusive ownership.
class Bathroom {
  final String id;
  final String name;
  final String createdBy;
  final String? classification;

  /// Null preserves the legacy palette index without reinterpreting it as RGB.
  final int? accentRgb;
  final String? _emoji;
  final int? _accent;
  String get emoji => _emoji ?? defaultEmoji(id, name);
  int get accent => _accent ?? stableIndex(id) % 6;

  // Historical identity fallback: do not reorder or replace; picker suggestions live separately.
  static const emojis = ['🚽', '👑', '📚', '🌿', '🔧', '🌈', '🏛️', '🧪'];
  static const emojiNames = [
    'Sanita',
    'Coroa',
    'Livros',
    'Natureza',
    'Ferramentas',
    'Arco-íris',
    'Edifício',
    'Laboratório',
  ];
  static const accentNames = [
    'Âmbar',
    'Oceano',
    'Lavanda',
    'Floresta',
    'Rosa',
    'Terracota',
  ];
  static int stableIndex(String id) =>
      id.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
  static String defaultEmoji(String id, String name) {
    if (name == 'Biblioteca') return '📚';
    if (name == 'DEM - 3º piso') return '🔧';
    if (name.startsWith('CP -')) return '🏛️';
    return emojis[stableIndex(id) % emojis.length];
  }

  const Bathroom({
    required this.id,
    required this.name,
    required this.createdBy,
    this.classification,
    this.accentRgb,
    String? emoji,
    int? accent,
  }) : _emoji = emoji,
       _accent = accent;
}
