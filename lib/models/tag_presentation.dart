import 'package:characters/characters.dart';

/// Canonical structured tags, legacy conversion and label equivalence.
abstract final class TagPresentation {
  static const recognized = {
    'wtf': '😵',
    'no like': '👎',
    'sad but true': '😔',
    'selva interior': '🪴',
    'arte nas paredes': '🎨',
    'nice': '✨',
    'cozy': '🛋️',
    'dark': '🌒',
    'grafiti': '🎨',
    'graffiti': '🎨',
    'small': '🤏',
    'great view': '🌅',
    'noisy': '📣',
    'silenciosa': '🤫',
    'privacidade': '🔒',
    'acessível': '♿',
    'sem sabonete': '🚰',
    'espelho gigante': '🪞',
    'música ambiente': '🎵',
    'vista panorâmica': '🌅',
    'plantas': '🪴',
    'hidden gem': '💎',
    'gancho para mochila': '🪝',
  };

  static bool hasEmoji(Object value) {
    final tag = value.toString();
    return ReviewTagData.validEmoji(
      tag.trimLeft().characters.firstOrNull ?? '',
    );
  }

  static String key(Object tag) {
    var label = (tag is ReviewTagData ? tag.label : tag.toString())
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    if (tag is! ReviewTagData && hasEmoji(label) && label.contains(' ')) {
      label = label.substring(label.indexOf(' ') + 1).trim();
    }
    return label == 'grafiti' ? 'graffiti' : label;
  }

  static String? decoration(Object tag) => tag is ReviewTagData
      ? tag.emoji
      : hasEmoji(tag)
      ? null
      : recognized[key(tag)] ?? '🏷️';

  static String display(Object tag) => tag is ReviewTagData
      ? '${tag.emoji} ${tag.label}'
      : hasEmoji(tag)
      ? tag.toString()
      : '${decoration(tag)} $tag';
}

class ReviewTagData {
  final String emoji;
  final String label;
  ReviewTagData({required String emoji, required String label})
    : emoji = emoji.trim(),
      label = label.trim().replaceAll(RegExp(r'\s+'), ' ') {
    if (!validEmoji(this.emoji) ||
        this.label.isEmpty ||
        this.label.characters.length > 30 ||
        label.contains(RegExp(r'[\n\r,]'))) {
      throw ArgumentError('Invalid tag emoji or label');
    }
  }

  factory ReviewTagData.legacy(String text) {
    final value = text.trim();
    final first = value.characters.firstOrNull ?? '';
    final prefixed = validEmoji(first);
    return ReviewTagData(
      emoji: prefixed
          ? first
          : TagPresentation.recognized[TagPresentation.key(value)] ?? '🏷️',
      label: prefixed ? value.substring(first.length).trim() : value,
    );
  }

  // One extended grapheme: supports ZWJ families, modifiers, flags and keycaps.
  // Reject letters, isolated modifiers/selectors, and arbitrary symbol strings.
  static bool validEmoji(String value) {
    if (value.characters.length != 1) return false;
    final points = value.runes.toList();
    if (points.isEmpty) return false;
    final first = points.first;
    if (first == 0x200d ||
        first == 0xfe0f ||
        (first >= 0x1f3fb && first <= 0x1f3ff)) {
      return false;
    }
    if (first >= 0x1f1e6 && first <= 0x1f1ff) {
      return points.length == 2 &&
          points.last >= 0x1f1e6 &&
          points.last <= 0x1f1ff;
    }
    if (first == 0x23 || first == 0x2a || (first >= 0x30 && first <= 0x39)) {
      return points.last == 0x20e3;
    }
    return (first >= 0x1f000 && first <= 0x1faff) ||
        (first >= 0x2600 && first <= 0x27bf) ||
        [
          0xa9,
          0xae,
          0x203c,
          0x2049,
          0x2122,
          0x2139,
          0x231a,
          0x231b,
          0x2328,
          0x23cf,
          0x23e9,
          0x23ea,
          0x23eb,
          0x23ec,
          0x23ed,
          0x23ee,
          0x23ef,
          0x23f0,
          0x23f1,
          0x23f2,
          0x23f3,
          0x23f8,
          0x23f9,
          0x23fa,
          0x24c2,
          0x2b50,
          0x2b55,
          0x3030,
          0x303d,
          0x3297,
          0x3299,
        ].contains(first);
  }

  Map<String, String> toJson() => {'emoji': emoji, 'label': label};
  factory ReviewTagData.fromJson(Map<String, dynamic> json) => ReviewTagData(
    emoji: json['emoji'] as String,
    label: json['label'] as String,
  );
  @override
  String toString() => label;
  @override
  bool operator ==(Object other) =>
      other is ReviewTagData && other.emoji == emoji && other.label == label;
  @override
  int get hashCode => Object.hash(emoji, label);
}
