import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../models/review.dart';
import '../models/tag_presentation.dart';
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
  final _categoryFocus = {
    for (final label in ['Higiene', 'Conforto', 'Estética', 'Papel'])
      label: FocusNode(),
  };
  double? _rating;
  String? _visitId;
  bool _visitInitialized = false;
  bool _saving = false;
  final _tagInput = TextEditingController();
  final List<ReviewTagData> _tags = [];
  final _emojiInput = TextEditingController(text: '🏷️');
  final _comment = TextEditingController();
  String? _tagError;
  bool _creatingTag = false;
  static final _suggestions = [
    '🪞 Espelho gigante',
    '🎵 Música ambiente',
    '🪴 Selva interior',
    '🌅 Vista panorâmica',
    '🎨 Arte nas paredes',
    '🪝 Gancho para mochila',
  ].map(ReviewTagData.legacy).toList();
  int? _hygiene, _comfort, _aesthetics, _paper;
  @override
  void initState() {
    super.initState();
    final r = widget.review;
    _rating = r?.rating;
    _comment.text = r?.comment ?? '';
    _tags.addAll(r?.tags ?? []);
    _hygiene = r?.hygiene;
    _comfort = r?.comfort;
    _aesthetics = r?.aesthetics;
    _paper = r?.paperAvailability;
  }

  VoidCallback? _releaseDraft;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _releaseDraft ??= context.read<AppState>().retainDraft();
  }

  @override
  void dispose() {
    _releaseDraft?.call();
    _tagInput.dispose();
    _emojiInput.dispose();
    _comment.dispose();
    _search.dispose();
    _scroll.dispose();
    _tagFocus.dispose();
    for (final node in _categoryFocus.values) {
      node.dispose();
    }
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
      if (!ReviewTagData.validEmoji(_emojiInput.text.trim())) {
        _tagError = 'Escolhe um único emoji válido.';
      } else if (tag.contains('\u0000')) {
        _tagError =
            'A etiqueta contém um carácter nulo. Remove-o antes de adicionar.';
      } else if (tag.isEmpty ||
          tag.characters.length > 30 ||
          tag.contains(RegExp(r'[\n\r,]'))) {
        _tagError = 'Usa uma etiqueta por vez, até 30 caracteres.';
      } else if (_tags.length >= 10) {
        _tagError = 'Podes adicionar até 10 etiquetas.';
      } else if (_tags.any(
        (t) => TagPresentation.key(t) == TagPresentation.key(tag),
      )) {
        _tagError = 'Esta etiqueta já está selecionada.';
      } else {
        _tags.add(ReviewTagData(emoji: _emojiInput.text, label: tag));
        _tagInput.clear();
        _tagError = null;
      }
    });
    if (_tagError != null) _tagFocus.requestFocus();
  }

  void _save() async {
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
    if (_comment.text.contains('\u0000')) {
      setState(
        () => _tagError =
            'O comentário contém um carácter nulo. Remove-o antes de guardar.',
      );
      return;
    }
    if (_comment.text.trim().characters.length > 500) return;

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
          comment: _comment.text,
        ),
        newVisit: visit,
      );
      await state.persistenceComplete;
      if (!mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
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

  bool _allowPop = false;
  bool _confirming = false;
  Future<void> _back() async {
    if (_confirming || _saving) return;
    if (_step > 0) {
      _go(_step - 1);
      return;
    }
    final original = widget.review;
    final dirty =
        _rating != original?.rating ||
        _hygiene != original?.hygiene ||
        _comfort != original?.comfort ||
        _aesthetics != original?.aesthetics ||
        _paper != original?.paperAvailability ||
        _tagInput.text.isNotEmpty ||
        (_creatingTag && _emojiInput.text != '🏷️') ||
        _comment.text.trim() != (original?.comment ?? '') ||
        _tags.join('\n') != (original?.tags ?? []).join('\n');
    _confirming = true;
    final discard =
        !dirty ||
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Descartar avaliação?'),
                content: const Text(
                  'As alterações desta avaliação serão perdidas.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Continuar a avaliar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Descartar'),
                  ),
                ],
              ),
            ) ==
            true;
    _confirming = false;
    if (discard && mounted) {
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Widget _category(
    String label,
    int? value,
    int max,
    String Function(Review) describe,
    ValueChanged<int> change,
  ) {
    final descriptions = [for (var i = 0; i <= max; i++) describe(_example(i))];
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  value == null
                      ? 'Por responder'
                      : descriptions[value].split(' ').skip(1).join(' '),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final cell = constraints.maxWidth / (max + 1);
            return Column(
              children: [
                Row(
                  children: [
                    for (var i = 0; i <= max; i++)
                      Expanded(
                        child: Semantics(
                          selected: value == i,
                          child: Tooltip(
                            message: descriptions[i],
                            excludeFromSemantics: true,
                            child: TextButton(
                              key: ValueKey('$label-$i'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(48, 48),
                                backgroundColor: value == i
                                    ? theme.colorScheme.secondaryContainer
                                    : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: value == i
                                    ? BorderSide(
                                        color: theme.colorScheme.primary,
                                        width: 2,
                                      )
                                    : BorderSide.none,
                              ),
                              onPressed: () => setState(() => change(i)),
                              child: Semantics(
                                label: '$label: ${descriptions[i]}',
                                child: ExcludeSemantics(
                                  child: FittedBox(
                                    child: Text(
                                      descriptions[i].split(' ').first,
                                      textScaler: TextScaler.noScaling,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontFamilyFallback: [
                                          'Noto Color Emoji',
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: cell / 2),
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      showValueIndicator: ShowValueIndicator.never,
                      trackShape: const RectangularSliderTrackShape(),
                      // Keep the full touch target and geometry before answering.
                      thumbColor: value == null ? Colors.transparent : null,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                        elevation: 0,
                        pressedElevation: 0,
                      ),
                    ),
                    child: MergeSemantics(
                      child: Semantics(
                        label: label,
                        child: CallbackShortcuts(
                          bindings: {
                            const SingleActivator(
                              LogicalKeyboardKey.home,
                            ): () =>
                                setState(() => change(0)),
                            const SingleActivator(LogicalKeyboardKey.end): () =>
                                setState(() => change(max)),
                          },
                          child: Slider(
                            key: ValueKey('$label-slider'),
                            focusNode: _categoryFocus[label],
                            onChangeStart: (_) =>
                                _categoryFocus[label]!.requestFocus(),
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            value: (value ?? 0).toDouble(),
                            min: 0,
                            max: max.toDouble(),
                            divisions: max,
                            semanticFormatterCallback: (v) =>
                                value == null && v == 0
                                ? 'Por responder'
                                : descriptions[v.round()],
                            onChanged: (v) => setState(() => change(v.round())),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
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
          style: const TextStyle(
            fontSize: 64,
            fontFamilyFallback: ['Noto Color Emoji'],
          ),
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
          'Move o cursor para avaliar. No início, escolhes zero.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _tagStep(AppState state) {
    final known = <String, ReviewTagData>{
      for (final tag in {
        ..._suggestions,
        for (final r in state.reviews) ...r.tags,
      })
        TagPresentation.key(tag): tag,
    }.values.toList();
    final query = _search.text.trim().toLowerCase();
    final suggestions = known
        .where(
          (t) =>
              !_tags.any(
                (selected) =>
                    TagPresentation.key(selected) == TagPresentation.key(t),
              ) &&
              TagPresentation.key(t).contains(TagPresentation.key(query)),
        )
        .take(query.isEmpty ? 6 : 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Etiquetas e comentário',
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
                  avatar: TagPresentation.decoration(tag) == null
                      ? null
                      : Text(
                          TagPresentation.decoration(tag)!,
                          style: const TextStyle(
                            fontFamilyFallback: ['Noto Color Emoji'],
                          ),
                        ),
                  label: Text(
                    tag.label,
                    style: const TextStyle(
                      fontFamilyFallback: ['Noto Color Emoji'],
                    ),
                  ),
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
                avatar: TagPresentation.decoration(tag) == null
                    ? null
                    : Text(
                        TagPresentation.decoration(tag)!,
                        style: const TextStyle(
                          fontFamilyFallback: ['Noto Color Emoji'],
                        ),
                      ),
                label: Text(
                  tag.label,
                  style: const TextStyle(
                    fontFamilyFallback: ['Noto Color Emoji'],
                  ),
                ),
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
          Wrap(
            spacing: 4,
            children: [
              for (final emoji in ['🏷️', '✨', '🌿', '👑', '🧻', '🎵'])
                ChoiceChip(
                  label: Text(
                    emoji,
                    style: const TextStyle(
                      fontFamilyFallback: ['Noto Color Emoji'],
                    ),
                  ),
                  selected: _emojiInput.text == emoji,
                  onSelected: (_) => setState(() => _emojiInput.text = emoji),
                ),
            ],
          ),
          TextField(
            controller: _emojiInput,
            style: const TextStyle(fontFamilyFallback: ['Noto Color Emoji']),
            decoration: const InputDecoration(
              labelText: 'Emoji',
              hintText: 'Usa o teclado de emojis',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            'Pré-visualização: ${_emojiInput.text} ${_tagInput.text}',
            style: const TextStyle(fontFamilyFallback: ['Noto Color Emoji']),
          ),
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
            onChanged: (_) => setState(() {}),
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
        const SizedBox(height: 24),
        TextField(
          controller: _comment,
          minLines: 3,
          maxLines: 6,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Comentário (opcional)',
            hintText: 'Como foi a tua experiência?',
          ),
        ),
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
      _visitId = widget.visitId;
      _visitInitialized = true;
    }
    final allowed =
        widget.review == null ||
        (widget.review!.authorId == state.currentUserId &&
            widget.review!.bathroomId == widget.bathroomId);
    final validStep = _step == 0
        ? _rating != null
        : [_hygiene, _comfort, _aesthetics, _paper].every((v) => v != null);
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _back),
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
                                            FittedBox(
                                              child: Text(
                                                [
                                                  'Global',
                                                  'Detalhes',
                                                  'Etiquetas',
                                                ][i],
                                              ),
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
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
                      if (state.communityEnabled && widget.review == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'A tua avaliação será pública e anónima: notas, etiquetas e comentário. Não incluas dados pessoais. A visita, a data exata e o email ficam privados.',
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
      ),
    );
  }
}

/// Decorative fractional stars followed by an explicit adjustable slider.
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
            return Column(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.transparent, width: 2),
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
                ExcludeSemantics(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      showValueIndicator: ShowValueIndicator.never,
                      thumbColor: value == null ? Colors.transparent : null,
                    ),
                    child: Slider(
                      key: const ValueKey('global-rating-slider'),
                      value: value ?? 0,
                      min: 0,
                      max: 5,
                      divisions: 50,
                      onChangeStart: (v) {
                        Focus.of(context).requestFocus();
                        _set(v);
                      },
                      onChanged: _set,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
