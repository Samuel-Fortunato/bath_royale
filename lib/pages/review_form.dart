import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/review.dart';
import '../models/bathroom_descriptions.dart';
import '../state/app_state.dart';

class ReviewFormPage extends StatefulWidget {
  final String bathroomId;
  final Review? review;
  const ReviewFormPage({super.key, required this.bathroomId, this.review});
  @override
  State<ReviewFormPage> createState() => _ReviewFormPageState();
}

class _ReviewFormPageState extends State<ReviewFormPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _rating;
  late final TextEditingController _tags;
  int? _hygiene, _comfort, _aesthetics, _paper;
  @override
  void initState() {
    super.initState();
    final r = widget.review;
    _rating = TextEditingController(text: r?.rating.toString() ?? '');
    _tags = TextEditingController(text: r?.tags.join(', ') ?? '');
    _hygiene = r?.hygiene;
    _comfort = r?.comfort;
    _aesthetics = r?.aesthetics;
    _paper = r?.paperAvailability;
  }

  @override
  void dispose() {
    _rating.dispose();
    _tags.dispose();
    super.dispose();
  }

  Review _example(int value) => Review(
    id: 'description',
    bathroomId: widget.bathroomId,
    authorId: 'local',
    createdAt: DateTime.utc(2026),
    rating: 0,
    paperAvailability: value > 2 ? 2 : value,
    hygiene: value,
    comfort: value,
    aesthetics: value,
  );

  void _save() {
    if (!_form.currentState!.validate()) return;
    final state = context.read<AppState>();
    final old = widget.review;
    final now = DateTime.now();
    var id = 'local-${now.microsecondsSinceEpoch}';
    while (state.reviews.any((r) => r.id == id)) {
      id = '$id-1';
    }
    try {
      state.saveReview(
        Review(
          id: old?.id ?? id,
          bathroomId: widget.bathroomId,
          authorId: old?.authorId ?? state.currentUserId,
          createdAt: old?.createdAt ?? now,
          updatedAt: old != null && old.updatedAt.isAfter(now)
              ? old.updatedAt
              : now,
          rating: double.parse(_rating.text.trim().replaceAll(',', '.')),
          paperAvailability: _paper!,
          hygiene: _hygiene!,
          comfort: _comfort!,
          aesthetics: _aesthetics!,
          tags: _tags.text.trim().isEmpty
              ? []
              : _tags.text.split(',').map((t) => t.trim()).toSet().toList(),
        ),
      );
      Navigator.of(context).pop();
    } on StateError {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível guardar esta avaliação.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final allowed =
        widget.review == null ||
        (widget.review!.authorId == state.currentUserId &&
            widget.review!.bathroomId == widget.bathroomId);
    Widget category(
      String label,
      int? value,
      int max,
      String Function(Review) describe,
      ValueChanged<int?> change,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<int>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (var i = 0; i <= max; i++)
            DropdownMenuItem(value: i, child: Text(describe(_example(i)))),
        ],
        onChanged: change,
        validator: (v) => v == null ? 'Escolhe uma opção' : null,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.review == null ? 'Nova avaliação' : 'Editar avaliação',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: !allowed
              ? const Text('Só podes editar as tuas avaliações.')
              : Form(
                  key: _form,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Conta como foi a experiência. Avaliar não regista uma visita.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _rating,
                          decoration: const InputDecoration(
                            labelText: 'Avaliação global (0–5)',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (value) {
                            final score = double.tryParse(
                              (value ?? '').trim().replaceAll(',', '.'),
                            );
                            return score == null ||
                                    !score.isFinite ||
                                    score < 0 ||
                                    score > 5
                                ? 'Indica um número entre 0 e 5'
                                : null;
                          },
                        ),
                        const SizedBox(height: 16),
                        category(
                          'Higiene',
                          _hygiene,
                          4,
                          (r) => r.hygieneText,
                          (v) => _hygiene = v,
                        ),
                        category(
                          'Conforto',
                          _comfort,
                          4,
                          (r) => r.comfortText,
                          (v) => _comfort = v,
                        ),
                        category(
                          'Estética',
                          _aesthetics,
                          4,
                          (r) => r.aestheticText,
                          (v) => _aesthetics = v,
                        ),
                        category(
                          'Papel',
                          _paper,
                          2,
                          (r) => r.paperText,
                          (v) => _paper = v,
                        ),
                        TextFormField(
                          controller: _tags,
                          decoration: const InputDecoration(
                            labelText: 'Etiquetas (opcional)',
                            helperText:
                                'Separadas por vírgulas; até 10, com 30 caracteres cada.',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) return null;
                            final tags = value!
                                .split(',')
                                .map((t) => t.trim())
                                .toList();
                            return tags.length > 10 ||
                                    tags.any(
                                      (t) =>
                                          t.isEmpty ||
                                          t.length > 30 ||
                                          t.contains('\n'),
                                    )
                                ? 'Usa até 10 etiquetas não vazias, com até 30 caracteres.'
                                : null;
                          },
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _save,
                          child: const Text('Guardar avaliação'),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
