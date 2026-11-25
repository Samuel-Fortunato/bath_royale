import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../models/review.dart';
import '../models/visit.dart';
import 'bathroom_details.dart' show reviewDate;
import '../models/bathroom_descriptions.dart';
import '../state/app_state.dart';

class ReviewFormPage extends StatefulWidget {
  final String bathroomId;
  final Review? review;
  final String? visitId;
  final bool canCreateCustomTags;
  const ReviewFormPage({
    super.key,
    required this.bathroomId,
    this.review,
    this.visitId,
    this.canCreateCustomTags = true,
  });
  @override
  State<ReviewFormPage> createState() => _ReviewFormPageState();
}

class _ReviewFormPageState extends State<ReviewFormPage> {
  int _step = 0;
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _tagFocus = FocusNode();
  double? _rating;
  String? _visitId;
  bool _visitInitialized = false;
  bool _saving = false;
  final _tagInput = TextEditingController();
  final List<String> _tags = [];
  String? _tagError;
  bool _creatingTag = false;
  static const _suggestions = [
    '🪞 Espelho gigante',
    '🎵 Música ambiente',
    '🪴 Selva interior',
    '🌅 Vista panorâmica',
    '🎨 Arte nas paredes',
    '🪝 Gancho para mochila',
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
    _search.dispose();
    _scroll.dispose();
    _tagFocus.dispose();
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
      } else if (_tags.any((t) => t.toLowerCase() == tag.toLowerCase())) {
        _tagError = 'Esta etiqueta já está selecionada.';
      } else {
        _tags.add(tag);
        _tagInput.clear();
        _tagError = null;
      }
    });
    if (_tagError != null) _tagFocus.requestFocus();
  }

  void _save() {
    if (_rating == null ||
        [_hygiene, _comfort, _aesthetics, _paper].contains(null)) {
      return;
    }
    if (_tagInput.text.trim().isNotEmpty) {
      setState(() {
        _creatingTag = true;
        _tagError = 'Adiciona ou apaga a etiqueta antes de guardar.';
      });
      _tagFocus.requestFocus();
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

    if (_saving) return;
    final state = context.read<AppState>();
    final old = widget.review;
    final now = DateTime.now();
    final id = AppState.newEntityId();
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

  void _go(int step) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _step = step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _chooseVisit(AppState state) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .6,
          child: Column(
            children: [
              Text(
                'Que experiência estás a avaliar?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      title: const Text('Acabei de visitar'),
                      selected: _visitId == null,
                      onTap: () => Navigator.pop(context, ''),
                    ),
                    for (final visit
                        in state
                            .visitsFor(widget.bathroomId)
                            .where((v) => state.reviewForVisit(v.id) == null))
                      ListTile(
                        title: Text(
                          'Uma visita anterior · ${reviewDate(visit.visitedAt)}',
                        ),
                        selected: _visitId == visit.id,
                        onTap: () => Navigator.pop(context, visit.id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && result != null) {
      setState(() => _visitId = result.isEmpty ? null : result);
    }
  }

  Widget _category(
    String label,
    int? value,
    int max,
    String Function(Review) describe,
    ValueChanged<int> change,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns = (constraints.maxWidth / (100 * scale))
                .floor()
                .clamp(2, max + 1);
            final width = (constraints.maxWidth - (columns - 1) * 6) / columns;
            return Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i <= max; i++)
                  SizedBox(
                    width: width,
                    child: Semantics(
                      selected: value == i,
                      child: OutlinedButton(
                        key: ValueKey('$label-$i'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 12,
                          ),
                          backgroundColor: value == i
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                          side: BorderSide(
                            color: value == i
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                            width: value == i ? 2 : 1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => setState(() => change(i)),
                        child: Column(
                          children: [
                            Text(
                              describe(_example(i)).split(' ').first,
                              style: const TextStyle(fontSize: 26),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              describe(
                                _example(i),
                              ).split(' ').skip(1).join(' '),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            SizedBox(
                              height: 18,
                              child: value == i
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _global(AppState state) {
    final visitId = widget.review?.visitId ?? _visitId;
    final visits = state
        .visitsFor(widget.bathroomId)
        .where((v) => v.id == visitId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                visitId == null
                    ? 'Acabei de visitar'
                    : visits.isEmpty
                    ? 'Visita indisponível'
                    : reviewDate(visits.first.visitedAt),
              ),
            ),
            if (widget.review == null && widget.visitId == null)
              TextButton(
                onPressed: () => _chooseVisit(state),
                child: const Text('Alterar'),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Como foi a experiência?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        Text(
          _rating == null ? '🚽' : _exampleRating(_rating!).emojiRating(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 64),
        ),
        const SizedBox(height: 16),
        Text(
          _rating == null ? '— / 5' : '${ratingNumber(_rating!)} / 5',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 16),
        StarRatingInput(
          value: _rating,
          onChanged: (value) => setState(() => _rating = value),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text('Terrível')),
            Expanded(child: Text('Perfeito', textAlign: TextAlign.end)),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Toca ou arrasta sobre as estrelas. No início, escolhes zero.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _tagStep(AppState state) {
    final known = {
      ..._suggestions,
      for (final r in state.reviews) ...r.tags,
    }.toList();
    final query = _search.text.trim().toLowerCase();
    final suggestions = known
        .where((t) => !_tags.contains(t) && t.toLowerCase().contains(query))
        .take(query.isEmpty ? 6 : 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'O que torna este trono especial?',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'As etiquetas são opcionais. Escolhe as que descrevem a tua experiência.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Procurar etiquetas',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Selecionadas (${_tags.length}/10)'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final tag in _tags)
                InputChip(
                  label: Text(tag),
                  deleteButtonTooltipMessage: 'Remover $tag',
                  onDeleted: () => setState(() {
                    _tags.remove(tag);
                    _tagError = null;
                  }),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text(query.isEmpty ? 'Sugestões' : 'Resultados (até 12)'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final tag in suggestions)
              ActionChip(
                label: Text(tag),
                onPressed: () => setState(() {
                  if (_tags.length < 10) {
                    _tags.add(tag);
                    _tagError = null;
                  } else {
                    _tagError = 'Podes adicionar até 10 etiquetas.';
                  }
                }),
              ),
          ],
        ),
        if (suggestions.isEmpty) const Text('Sem etiquetas encontradas.'),
        if (widget.canCreateCustomTags)
          TextButton.icon(
            onPressed: () => setState(() => _creatingTag = !_creatingTag),
            icon: const Icon(Icons.add),
            label: const Text('Inventar uma etiqueta'),
          ),
        if (_creatingTag) ...[
          TextField(
            controller: _tagInput,
            focusNode: _tagFocus,
            maxLength: 30,
            decoration: InputDecoration(
              errorText: _tagError,
              errorMaxLines: 3,
              labelText: 'A tua etiqueta',
              hintText: 'Algo que só este trono tem…',
            ),
            onSubmitted: (_) => _addTag(),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _creatingTag = false;
                  _tagInput.clear();
                  _tagError = null;
                }),
                child: const Text('Cancelar etiqueta'),
              ),
              TextButton(
                onPressed: _addTag,
                child: const Text('Adicionar etiqueta'),
              ),
            ],
          ),
        ],
        if (_tagError != null && !_creatingTag)
          Semantics(
            liveRegion: true,
            child: Text(
              _tagError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!_visitInitialized) {
      final visits = state
          .visitsFor(widget.bathroomId)
          .where((v) => state.reviewForVisit(v.id) == null);
      _visitId = widget.visitId ?? (visits.isEmpty ? null : visits.first.id);
      _visitInitialized = true;
    }
    final allowed =
        widget.review == null ||
        (widget.review!.authorId == state.currentUserId &&
            widget.review!.bathroomId == widget.bathroomId);
    final validStep = _step == 0
        ? _rating != null
        : [_hygiene, _comfort, _aesthetics, _paper].every((v) => v != null);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.review == null ? 'Nova avaliação' : 'Editar avaliação',
        ),
      ),
      body: !allowed
          ? const Center(child: Text('Só podes editar as tuas avaliações.'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            state.allBathrooms
                                .firstWhere((b) => b.id == widget.bathroomId)
                                .name,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              for (var i = 0; i < 3; i++)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    child: Semantics(
                                      label: 'Passo ${i + 1} de 3',
                                      selected: i == _step,
                                      child: Column(
                                        children: [
                                          LinearProgressIndicator(
                                            value: i <= _step ? 1 : 0,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            [
                                              'Global',
                                              'Detalhes',
                                              'Etiquetas',
                                            ][i],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scroll,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: _step == 0
                            ? _global(state)
                            : _step == 1
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Os pequenos detalhes',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 20),
                                  _category(
                                    'Higiene',
                                    _hygiene,
                                    4,
                                    (r) => r.hygieneText,
                                    (v) => _hygiene = v,
                                  ),
                                  _category(
                                    'Conforto',
                                    _comfort,
                                    4,
                                    (r) => r.comfortText,
                                    (v) => _comfort = v,
                                  ),
                                  _category(
                                    'Estética',
                                    _aesthetics,
                                    4,
                                    (r) => r.aestheticText,
                                    (v) => _aesthetics = v,
                                  ),
                                  _category(
                                    'Papel',
                                    _paper,
                                    2,
                                    (r) => r.paperText,
                                    (v) => _paper = v,
                                  ),
                                ],
                              )
                            : _tagStep(state),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            if (_step > 0) ...[
                              TextButton(
                                onPressed: () => _go(_step - 1),
                                child: const Text('Voltar'),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: FilledButton(
                                onPressed: !validStep || _saving
                                    ? null
                                    : () {
                                        if (_step < 2) {
                                          _go(_step + 1);
                                        } else {
                                          _save();
                                        }
                                      },
                                child: Text(
                                  _step < 2
                                      ? 'Continuar'
                                      : _tags.isEmpty
                                      ? 'Guardar sem etiquetas'
                                      : 'Guardar avaliação',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// A single adjustable star strip. Each star clips its own fractional fill.
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final double? value;
  final ValueChanged<double> onChanged;

  void _set(double next) => onChanged((next.clamp(0, 5) * 10).round() / 10);

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Avaliação global',
    slider: true,
    value: value == null ? 'Sem resposta' : '${ratingNumber(value!)} de 5',
    increasedValue: ratingNumber(((value ?? 0) + .1).clamp(0, 5)),
    decreasedValue: ratingNumber(((value ?? 0) - .1).clamp(0, 5)),
    onIncrease: () => _set((value ?? 0) + .1),
    onDecrease: () => _set((value ?? 0) - .1),
    child: Focus(
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.home) {
          _set(0);
        } else if (key == LogicalKeyboardKey.end) {
          _set(5);
        } else if (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowUp) {
          _set((value ?? 0) + .1);
        } else if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowDown) {
          _set((value ?? 0) - .1);
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: Builder(
        builder: (context) => LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final focused = Focus.of(context).hasFocus;
            void update(Offset position) {
              Focus.of(context).requestFocus();
              _set(position.dx / width * 5);
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (event) => update(event.localPosition),
              onHorizontalDragStart: (event) => update(event.localPosition),
              onHorizontalDragUpdate: (event) => update(event.localPosition),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: focused
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ExcludeSemantics(
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        for (var i = 0; i < 5; i++)
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final size = box.maxWidth.clamp(0.0, 56.0);
                                final fraction = ((value ?? 0) - i).clamp(
                                  0.0,
                                  1.0,
                                );
                                return Center(
                                  child: SizedBox(
                                    width: size,
                                    height: size,
                                    child: Stack(
                                      children: [
                                        Icon(
                                          Icons.star_rounded,
                                          size: size,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.outlineVariant,
                                        ),
                                        ClipRect(
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            widthFactor: fraction,
                                            child: Icon(
                                              Icons.star_rounded,
                                              size: size,
                                              color: Colors.amber,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
