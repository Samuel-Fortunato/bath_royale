import '../models/content_suggestions.dart';
import '../widgets/alpha_feedback.dart';
import '../widgets/emoji_input.dart';
import '../widgets/accent_picker.dart';
import '../models/bathroom.dart';
import '../widgets/bathroom_identity.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'bathroom_details.dart';

class BathroomFormPage extends StatefulWidget {
  const BathroomFormPage({super.key});

  @override
  State<BathroomFormPage> createState() => _BathroomFormPageState();
}

class _BathroomFormPageState extends State<BathroomFormPage> {
  final _emoji = TextEditingController();
  int _accentRgb = randomAccent();
  bool _saving = false;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();

  VoidCallback? _releaseDraft;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _releaseDraft ??= context.read<AppState>().retainDraft();
  }

  @override
  void dispose() {
    _releaseDraft?.call();
    _name.dispose();
    _emoji.dispose();
    super.dispose();
  }

  void _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    _saving = true;
    final state = context.read<AppState>();
    final bathroom = state.createBathroom(
      _name.text,
      emoji: _emoji.text.trim(),
      accentRgb: _accentRgb,
    );
    await state.persistenceComplete;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'bathroom'),
        builder: (_) => ChangeNotifierProvider.value(
          value: state,
          child: BathroomDetailsPage(bathroomId: bathroom.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Novo trono')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Form(
          key: _form,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text('Descobriste um novo trono? 🚽'),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _name,
                      autofocus: true,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Nome da casa de banho',
                        helperText:
                            'Indica o local e uma referência fácil de encontrar.',
                        helperMaxLines: 3,
                        errorMaxLines: 3,
                      ),
                      validator: (value) => context
                          .read<AppState>()
                          .validateBathroomName(value ?? ''),
                      onFieldSubmitted: (_) => _save(),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: BathroomIdentity(
                        bathroom: Bathroom(
                          id: 'preview',
                          name: '',
                          createdBy: '',
                          emoji: _emoji.text.isEmpty ? '❔' : _emoji.text.trim(),
                          accentRgb: _accentRgb,
                        ),
                        size: 64,
                      ),
                    ),
                    EmojiInput(
                      controller: _emoji,
                      onChanged: (_) => setState(() {}),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final emoji in bathroomEmojiSuggestions)
                          IconButton(
                            tooltip: 'Escolher $emoji',
                            onPressed: () =>
                                setState(() => _emoji.text = emoji),
                            icon: Text(
                              emoji,
                              style: const TextStyle(
                                fontSize: 24,
                                fontFamilyFallback: ['Noto Color Emoji'],
                              ),
                            ),
                          ),
                      ],
                    ),
                    AccentPicker(
                      value: _accentRgb,
                      onChanged: (v) => setState(() => _accentRgb = v),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (AlphaFeedbackHost.isEnabledIn(context) &&
                          AlphaFeedbackConfig.onLeft)
                        const SizedBox(width: 64),
                      Expanded(
                        child: FilledButton(
                          onPressed: _save,
                          child: const Text('Criar casa de banho'),
                        ),
                      ),
                      if (AlphaFeedbackHost.isEnabledIn(context) &&
                          !AlphaFeedbackConfig.onLeft)
                        const SizedBox(width: 64),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
