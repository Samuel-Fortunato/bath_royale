import 'package:flutter/material.dart';
import '../models/bathroom.dart';

/// A persistent bathroom emblem; colour is decorative, never a status signal.
class BathroomIdentity extends StatelessWidget {
  final Bathroom bathroom;
  final double size;
  const BathroomIdentity({super.key, required this.bathroom, this.size = 48});
  static const seeds = [
    0xffac7900,
    0xff207799,
    0xff7953a8,
    0xff39815a,
    0xffa44878,
    0xffac593c,
  ];
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Color(seeds[bathroom.accent % seeds.length]),
      brightness: Theme.of(context).brightness,
    );
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(bathroom.emoji, style: TextStyle(fontSize: size * .52)),
      ),
    );
  }
}

Color ratingGold(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xffffd166)
    : const Color(0xff946600);

class ReviewTag extends StatelessWidget {
  final String tag;
  const ReviewTag(this.tag, {super.key});
  static const recognized = {
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
  @override
  Widget build(BuildContext context) {
    final emoji = recognized[tag.trim().toLowerCase()];
    // Existing emoji prefixes remain exactly as entered.
    final first = tag.trimLeft().runes.firstOrNull ?? 0;
    final prefixed = first >= 0x1f000 || (first >= 0x2600 && first <= 0x27ff);
    return Chip(
      avatar: prefixed
          ? null
          : emoji != null
          ? Text(emoji)
          : const Icon(Icons.label_outline, size: 18),
      label: Text(tag),
    );
  }
}

class CategoryLabel extends StatelessWidget {
  final int index;
  final String label;
  const CategoryLabel(this.index, this.label, {super.key});
  @override
  Widget build(BuildContext context) {
    final colors = [Colors.teal, Colors.deepPurple, Colors.pink, Colors.orange];
    final scheme = ColorScheme.fromSeed(
      seedColor: colors[index],
      brightness: Theme.of(context).brightness,
    );
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(
          [
            Icons.clean_hands_outlined,
            Icons.chair_outlined,
            Icons.palette_outlined,
            Icons.receipt_long_outlined,
          ][index],
          size: 18,
          color: scheme.primary,
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
