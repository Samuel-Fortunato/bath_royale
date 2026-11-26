import 'dart:math';
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
  String _emoji = '🚽';
  int _accent = 0;
  bool _saving = false;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    _saving = true;
    final state = context.read<AppState>();
    final bathroom = state.createBathroom(
      _name.text,
      emoji: _emoji,
      accent: _accent,
    );
    await state.persistenceComplete;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
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
                      'Inclui o edifício e o piso para distinguir os tronos.',
                  helperMaxLines: 3,
                  errorMaxLines: 3,
                ),
                validator: (value) =>
                    context.read<AppState>().validateBathroomName(value ?? ''),
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Confirma que ainda não existe. Criar não conta como visita nem avaliação.',
              ),
              const SizedBox(height: 24),
              Center(
                child: BathroomIdentity(
                  bathroom: Bathroom(
                    id: 'preview',
                    name: '',
                    createdBy: '',
                    emoji: _emoji,
                    accent: _accent,
                  ),
                  size: 64,
                ),
              ),
              const Text('Símbolo do trono'),
              Wrap(
                spacing: 8,
                children: [
                  for (final emoji in Bathroom.emojis)
                    ChoiceChip(
                      label: Semantics(
                        label:
                            Bathroom.emojiNames[Bathroom.emojis.indexOf(emoji)],
                        child: ExcludeSemantics(child: Text(emoji)),
                      ),
                      selected: _emoji == emoji,
                      onSelected: (_) => setState(() => _emoji = emoji),
                    ),
                ],
              ),
              const Text('Cor do trono'),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < Bathroom.accentNames.length; i++)
                    ChoiceChip(
                      avatar: Icon(
                        Icons.circle,
                        color: Color(BathroomIdentity.seeds[i]),
                        size: 16,
                      ),
                      label: Text(Bathroom.accentNames[i]),
                      selected: _accent == i,
                      onSelected: (_) => setState(() => _accent = i),
                    ),
                ],
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  final random = Random();
                  _emoji =
                      Bathroom.emojis[random.nextInt(Bathroom.emojis.length)];
                  _accent = random.nextInt(Bathroom.accentNames.length);
                }),
                icon: const Icon(Icons.shuffle),
                label: const Text('Surpreende-me'),
              ),

              FilledButton(
                onPressed: _save,
                child: const Text('Criar casa de banho'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
