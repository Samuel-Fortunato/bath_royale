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
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final state = context.read<AppState>();
    final bathroom = state.createBathroom(_name.text);
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
