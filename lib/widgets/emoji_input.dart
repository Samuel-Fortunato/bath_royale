import 'package:flutter/material.dart';
import '../models/tag_presentation.dart';

/// Shared unrestricted system-keyboard input. Suggestions never limit identity.
class EmojiInput extends StatelessWidget {
  const EmojiInput({super.key, required this.controller, this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    style: const TextStyle(
      fontSize: 24,
      fontFamilyFallback: ['Noto Color Emoji'],
    ),
    decoration: const InputDecoration(
      labelText: 'Emoji',
      hintText: 'Escolher no teclado',
      errorMaxLines: 2,
    ),
    validator: (v) => ReviewTagData.validEmoji((v ?? '').trim())
        ? null
        : 'Escolhe um único emoji.',
    onChanged: onChanged,
  );
}
