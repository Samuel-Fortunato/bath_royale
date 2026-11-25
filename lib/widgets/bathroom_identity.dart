import 'package:flutter/material.dart';
import '../models/bathroom.dart';
import '../models/tag_presentation.dart';

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
  static ColorScheme colors(BuildContext context, Bathroom bathroom) =>
      ColorScheme.fromSeed(
        seedColor: Color(seeds[bathroom.accent % seeds.length]),
        brightness: Theme.of(context).brightness,
      );
  @override
  Widget build(BuildContext context) {
    final scheme = colors(context, bathroom);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          bathroom.emoji,
          style: TextStyle(
            fontSize: size * .52,
            fontFamilyFallback: const ['Noto Color Emoji'],
          ),
        ),
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
  @override
  Widget build(BuildContext context) => Chip(
    avatar: TagPresentation.decoration(tag) == null
        ? null
        : Text(
            TagPresentation.decoration(tag)!,
            style: const TextStyle(fontFamilyFallback: ['Noto Color Emoji']),
          ),
    label: Text(
      tag,
      style: const TextStyle(fontFamilyFallback: ['Noto Color Emoji']),
    ),
  );
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
