/// Presentation and matching only: stored labels are never rewritten.
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

  static bool hasEmoji(String tag) {
    final first = tag.trimLeft().runes.firstOrNull ?? 0;
    return first >= 0x1f000 || (first >= 0x2600 && first <= 0x27ff);
  }

  static String key(String tag) {
    var label = tag.trim().toLowerCase();
    if (hasEmoji(label) && label.contains(' ')) {
      label = label.substring(label.indexOf(' ') + 1).trim();
    }
    return label == 'grafiti' ? 'graffiti' : label;
  }

  static String? decoration(String tag) =>
      hasEmoji(tag) ? null : recognized[key(tag)] ?? '🏷️';

  static String display(String tag) =>
      hasEmoji(tag) ? tag : '${decoration(tag)} $tag';
}
