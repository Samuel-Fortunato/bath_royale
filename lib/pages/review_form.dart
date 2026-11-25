import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../models/review.dart';
import '../models/visit.dart';
import 'bathroom_details.dart' show reviewDate;
import '../models/bathroom_descriptions.dart';
import '../state/app_state.dart';

class ReviewFormPage extends StatefulWidget {
  final String bathroomId;
  final Review? review;
  final String? visitId;
  const ReviewFormPage({
    super.key,
    required this.bathroomId,
    this.review,
    this.visitId,
  });
  @override
  State<ReviewFormPage> createState() => _ReviewFormPageState();
}

class _ReviewFormPageState extends State<ReviewFormPage> {
  final _form = GlobalKey<FormState>();
  double? _rating;
  String? _visitId;
  bool _visitInitialized = false;
  bool _saving = false;
  final _tagInput = TextEditingController();
  final List<String> _tags = [];
  String? _tagError;
  static const _suggestions = [
    '✨ Limpo',
    '🧻 Sem papel',
    '🔒 Privado',
    '♿ Acessível',
    '🌸 Cheiro agradável',
    '🚰 Sem sabonete',
  ];
  int? _hygiene, _comfort, _aesthetics, _paper;
  @override
  void initState() {
    super.initState();
    final r = widget.review;
    _rating = r?.rating;
    _tags.addAll(r?.tags ?? []);
    _hygiene = r?.hygiene;
    _comfort = r?.comfort;
    _aesthetics = r?.aesthetics;
    _paper = r?.paperAvailability;
  }

  @override
  void dispose() {
    _tagInput.dispose();
    super.dispose();
  }

  Review _example(int value) => Review(
    id: 'description',
    visitId: 'description',
    bathroomId: widget.bathroomId,
    authorId: 'local',
    createdAt: DateTime.utc(2026),
    rating: 0,
    paperAvailability: value > 2 ? 2 : value,
    hygiene: value,
    comfort: value,
    aesthetics: value,
  );

  Review _exampleRating(double rating) => Review(
    id: 'emoji',
    visitId: 'emoji',
    bathroomId: widget.bathroomId,
    authorId: 'local',
    createdAt: DateTime.utc(2026),
    rating: rating,
    paperAvailability: 0,
    hygiene: 0,
    comfort: 0,
    aesthetics: 0,
  );

  void _addTag() {
    final tag = _tagInput.text.trim();
    setState(() {
      if (tag.isEmpty || tag.length > 30 || tag.contains(RegExp(r'[\n\r,]'))) {
        _tagError = 'Usa uma etiqueta por vez, até 30 caracteres.';
      } else if (_tags.length >= 10 && !_tags.contains(tag)) {
        _tagError = 'Podes adicionar até 10 etiquetas.';
      } else {
        if (!_tags.contains(tag)) _tags.add(tag);
        _tagInput.clear();
        _tagError = null;
      }
    });
  }

  void _save() {
    final valid = _form.currentState!.validate();
    if (_tagInput.text.trim().isNotEmpty) {
      setState(
        () => _tagError = 'Adiciona ou apaga a etiqueta antes de guardar.',
      );
      return;
    }
    if (_tags.length > 10 ||
        _tags.any(
          (tag) =>
              tag.trim().isEmpty ||
              tag.length > 30 ||
              tag.contains(RegExp(r'[\n\r]')),
        )) {
      setState(
        () =>
            _tagError = 'Usa até 10 etiquetas válidas, com até 30 caracteres.',
      );
      return;
    }
    if (!valid) return;
    if (_saving) return;
    final state = context.read<AppState>();
    final old = widget.review;
    final now = DateTime.now();
    var id = 'local-${now.microsecondsSinceEpoch}';
    while (state.reviews.any((r) => r.id == id)) {
      id = '$id-1';
    }
    final visit = old == null && _visitId == null
        ? Visit(
            id: state.newVisitId(),
            bathroomId: widget.bathroomId,
            userId: state.currentUserId,
            visitedAt: now,
          )
        : null;
    _saving = true;
    try {
      state.saveReview(
        Review(
          id: old?.id ?? id,
          visitId: old?.visitId ?? visit?.id ?? _visitId!,
          bathroomId: widget.bathroomId,
          authorId: old?.authorId ?? state.currentUserId,
          createdAt: old?.createdAt ?? now,
          updatedAt: old != null && old.updatedAt.isAfter(now)
              ? old.updatedAt
              : now,
          rating: _rating!,
          paperAvailability: _paper!,
          hygiene: _hygiene!,
          comfort: _comfort!,
          aesthetics: _aesthetics!,
          tags: _tags,
        ),
        newVisit: visit,
      );
      Navigator.of(context).pop();
    } on StateError {
      _saving = false;
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
    final availableVisits = state
        .visitsFor(widget.bathroomId)
        .where((v) => state.reviewForVisit(v.id) == null)
        .toList();
    if (!_visitInitialized) {
      _visitId =
          widget.visitId ??
          (availableVisits.isEmpty ? null : availableVisits.first.id);
      _visitInitialized = true;
    }
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
                          'Conta como foi a experiência neste trono. 🚽',
                        ),
                        if (widget.review == null &&
                            widget.visitId == null) ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _visitId ?? '',
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Escolhe a visita',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              if (_visitId != null &&
                                  !availableVisits.any((v) => v.id == _visitId))
                                DropdownMenuItem(
                                  value: _visitId,
                                  enabled: false,
                                  child: const Text('Visita indisponível'),
                                ),
                              for (final visit in availableVisits)
                                DropdownMenuItem(
                                  value: visit.id,
                                  child: Text(
                                    'Visita de ${reviewDate(visit.visitedAt)}',
                                  ),
                                ),
                              const DropdownMenuItem(
                                value: '',
                                child: Text('Nova visita agora'),
                              ),
                            ],
                            onChanged: (value) => setState(
                              () => _visitId = value == '' ? null : value,
                            ),
                          ),
                        ] else if (widget.review != null ||
                            widget.visitId != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('Avaliação desta visita'),
                          ),

                        const SizedBox(height: 16),
                        FormField<double>(
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          initialValue: _rating,
                          validator: (_) =>
                              _rating == null ? 'Escolhe uma avaliação' : null,
                          builder: (field) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Avaliação global',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  KeyedSubtree(
                                    key: ValueKey(_rating),
                                    child: RatingBar.builder(
                                      initialRating: _rating ?? 0,
                                      minRating: 0,
                                      allowHalfRating: true,
                                      itemSize: 36,
                                      itemPadding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      itemBuilder: (_, _) => const Icon(
                                        Icons.star_rounded,
                                        color: Colors.amber,
                                      ),
                                      onRatingUpdate: (value) {
                                        setState(() => _rating = value);
                                        field.didChange(value);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      child: Text(
                                        _rating == null
                                            ? 'Escolhe'
                                            : '${_exampleRating(_rating!).emojiRating()} ${_rating!.toStringAsFixed(1)} / 5',
                                        key: ValueKey(_rating),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: _rating ?? 0,
                                min: 0,
                                max: 5,
                                divisions: 50,
                                label: (_rating ?? 0).toStringAsFixed(1),
                                onChanged: (value) {
                                  setState(() => _rating = value);
                                  field.didChange(value);
                                },
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() => _rating = 0);
                                  field.didChange(0);
                                },
                                child: const Text('Dar zero'),
                              ),
                              if (field.hasError)
                                Text(
                                  field.errorText!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
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
                        Text(
                          'Etiquetas',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final tag in _suggestions)
                              FilterChip(
                                label: Text(tag),
                                selected: _tags.contains(tag),
                                onSelected: (selected) => setState(() {
                                  if (selected) {
                                    if (_tags.length < 10) {
                                      _tags.add(tag);
                                      _tagError = null;
                                    } else {
                                      _tagError =
                                          'Podes adicionar até 10 etiquetas.';
                                    }
                                  } else {
                                    _tags.remove(tag);
                                    _tagError = null;
                                  }
                                }),
                              ),
                            for (final tag in _tags.where(
                              (t) => !_suggestions.contains(t),
                            ))
                              InputChip(
                                label: Text(tag),
                                onDeleted: () => setState(() {
                                  _tags.remove(tag);
                                  _tagError = null;
                                }),
                              ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _tagInput,
                                maxLength: 30,
                                decoration: InputDecoration(
                                  labelText: 'Outra etiqueta',
                                  errorText: _tagError,
                                ),
                                onSubmitted: (_) => _addTag(),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Adicionar etiqueta',
                              onPressed: _addTag,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
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
