import '../models/content_suggestions.dart';
import '../widgets/alpha_feedback.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import '../widgets/emoji_input.dart';
import 'privacy.dart';
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
  double? _rating;
  String? _visitId;
  bool _visitInitialized = false;
  bool _saving = false;
  final _tagInput = TextEditingController();
  final List<ReviewTagData> _tags = [];
  final _emojiInput = TextEditingController(text: '🏷️');
  final _comment = TextEditingController();
  String? _tagError;
  List<ReviewTagData>? _draftSuggestions;
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

  Future<void> _createTag() async {
    final form = GlobalKey<FormState>();
    var emojiSuggestions = randomEmojiSuggestions();
    _tagInput.clear();
    _emojiInput.clear();
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Criar etiqueta'),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EmojiInput(controller: _emojiInput),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final emoji in emojiSuggestions)
                        IconButton(
                          tooltip: 'Escolher $emoji',
                          onPressed: () =>
                              refresh(() => _emojiInput.text = emoji),
                          icon: Text(
                            emoji,
                            style: const TextStyle(
                              fontSize: 24,
                              fontFamilyFallback: ['Noto Color Emoji'],
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: 'Outros emojis',
                        onPressed: () => refresh(
                          () => emojiSuggestions = randomEmojiSuggestions(),
                        ),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _tagInput,
                    autofocus: true,
                    maxLength: 30,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Nome da etiqueta',
                      errorMaxLines: 3,
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty ||
                          value.characters.length > 30 ||
                          value.contains(RegExp(r'[\n\r,\x00]'))) {
                        return 'Usa um nome até 30 caracteres.';
                      }
                      if (_tags.any(
                        (t) =>
                            TagPresentation.key(t) ==
                            TagPresentation.key(value),
                      )) {
                        return 'Esta etiqueta já está selecionada.';
                      }
                      if (_tags.length >= 10) {
                        return 'Podes adicionar até 10 etiquetas.';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                setState(() {
                  _tags.add(
                    ReviewTagData(
                      emoji: _emojiInput.text.trim(),
                      label: _tagInput.text,
                    ),
                  );
                  _tagError = null;
                });
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Adicionar etiqueta'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (added == true) {
      _tagInput.clear();
      _emojiInput.clear();
    } else {
      _tagInput.clear();
      _emojiInput.clear();
    }
  }

  void _save() async {
    if (_rating == null ||
        [_hygiene, _comfort, _aesthetics, _paper].contains(null)) {
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
        modernRating: true,
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
    final original = widget.review;
    final dirty =
        _rating != original?.rating ||
        _hygiene != original?.hygiene ||
        _comfort != original?.comfort ||
        _aesthetics != original?.aesthetics ||
        _paper != original?.paperAvailability ||
        _tagInput.text.isNotEmpty ||
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, box) {
              final large = MediaQuery.textScalerOf(context).scale(12) > 16;
              Widget option(int i) => Semantics(
                selected: value == i,
                child: TextButton(
                  key: ValueKey('$label-$i'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 64),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 6,
                    ),
                    foregroundColor: scheme.onSurface,
                    backgroundColor: value == i
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerLow,
                    side: BorderSide(
                      color: value == i
                          ? scheme.primary
                          : scheme.outlineVariant,
                      width: value == i ? 2 : 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => setState(() => change(i)),
                  child: Semantics(
                    label: '$label: ${descriptions[i]}',
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            descriptions[i].split(' ').first,
                            style: const TextStyle(
                              fontSize: 20,
                              fontFamilyFallback: ['Noto Color Emoji'],
                            ),
                          ),
                          Text(
                            descriptions[i].split(' ').skip(1).join(' '),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.15,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
              if (large) {
                return Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i <= max; i++)
                      SizedBox(width: (box.maxWidth - 8) / 3, child: option(i)),
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i <= max; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i == max ? 0 : 4),
                          child: option(i),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
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
        StarRatingInput(
          value: _rating,
          onChanged: (value) => setState(() => _rating = value),
        ),
      ],
    );
  }

  Widget _tagStep(AppState state) {
    final known = <String, ReviewTagData>{
      for (final t in reviewTagSuggestions) TagPresentation.key(t): t,
      for (final r in state.reviews.where(
        (r) => r.authorId == state.currentUserId,
      ))
        for (final t in r.tags) TagPresentation.key(t): t,
      if (state.community != null)
        for (final r in state.community!.reviews)
          for (final t in r.tags) TagPresentation.key(t): t,
    }.values.toList();
    _draftSuggestions ??= List.of(known)..shuffle(Random());
    final query = TagPresentation.key(_search.text);
    final suggestions = (query.isEmpty ? _draftSuggestions! : known)
        .where(
          (t) =>
              !_tags.any(
                (s) => TagPresentation.key(s) == TagPresentation.key(t),
              ) &&
              TagPresentation.key(t).contains(query),
        )
        .take(query.isEmpty ? 6 : 12)
        .toList();
    Widget chip(ReviewTagData t, bool selected) => selected
        ? InputChip(
            avatar: Text(
              t.emoji,
              style: const TextStyle(fontFamilyFallback: ['Noto Color Emoji']),
            ),
            label: Text(t.label),
            onDeleted: () => setState(() {
              _tags.remove(t);
              _tagError = null;
            }),
          )
        : ActionChip(
            avatar: Text(
              t.emoji,
              style: const TextStyle(fontFamilyFallback: ['Noto Color Emoji']),
            ),
            label: Text(t.label),
            onPressed: () => setState(() {
              if (_tags.length < 10) {
                _tags.add(t);
                _tagError = null;
              } else {
                _tagError = 'Podes adicionar até 10 etiquetas.';
              }
            }),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _comment,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Comentário (opcional)',
            hintText: 'Como foi a tua experiência?',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              'Etiquetas (${_tags.length}/10)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (widget.canCreateCustomTags)
              TextButton(
                onPressed: _createTag,
                child: const Text('+ Criar etiqueta'),
              ),
          ],
        ),
        if (_tags.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 112),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 2,
                children: [for (final t in _tags) chip(t, true)],
              ),
            ),
          ),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Procurar etiquetas',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
        ),
        Row(
          children: [
            Expanded(child: Text(query.isEmpty ? 'Sugestões' : 'Resultados')),
            IconButton(
              tooltip: 'Outras sugestões',
              onPressed: () => setState(
                () => _draftSuggestions = List.of(known)..shuffle(Random()),
              ),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 150),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 2,
              children: [for (final t in suggestions) chip(t, false)],
            ),
          ),
        ),
        if (suggestions.isEmpty) const Text('Sem etiquetas encontradas.'),
        if (_tagError != null)
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
    FeedbackLocation.reviewStep = _step;
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
                      if (MediaQuery.viewInsetsOf(context).bottom == 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                state.allBathrooms
                                    .firstWhere(
                                      (b) => b.id == widget.bathroomId,
                                    )
                                    .name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
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
                      if (_step == 1 && !validStep)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text('Escolhe uma opção em cada categoria.'),
                        ),
                      if (_step == 2 &&
                          state.communityEnabled &&
                          widget.review == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const Text('Avaliação pública e anónima.'),
                              TextButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    settings: const RouteSettings(
                                      name: 'privacy',
                                    ),
                                    builder: (_) => const PrivacyPage(),
                                  ),
                                ),
                                child: const Text('Privacidade'),
                              ),
                            ],
                          ),
                        ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final split =
                                  _step > 0 &&
                                  box.maxWidth /
                                          MediaQuery.textScalerOf(
                                            context,
                                          ).scale(1) <
                                      260;
                              final feedback = AlphaFeedbackHost.isEnabledIn(
                                context,
                              );
                              final back = TextButton(
                                onPressed: () => _go(_step - 1),
                                child: const Text('Voltar'),
                              );
                              final primary = FilledButton(
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
                                  _step < 2 ? 'Continuar' : 'Guardar avaliação',
                                ),
                              );
                              final row = Row(
                                children: [
                                  if (feedback && AlphaFeedbackConfig.onLeft)
                                    const SizedBox(width: 64),
                                  if (_step > 0 && !split) ...[
                                    back,
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(child: primary),
                                  if (feedback && !AlphaFeedbackConfig.onLeft)
                                    const SizedBox(width: 64),
                                ],
                              );
                              return split
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [back, row],
                                    )
                                  : row;
                            },
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

/// Five direct integer choices; historical fractions remain visible and untouched.
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final double? value;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Avaliação global',
    value: value == null ? 'Sem resposta' : '${ratingNumber(value!)} de 5',
    child: Row(
      children: [
        for (var i = 1; i <= 5; i++)
          Expanded(
            child: Semantics(
              selected: value == i,
              child: IconButton(
                key: ValueKey('global-star-$i'),
                tooltip: '$i ${i == 1 ? 'estrela' : 'estrelas'}',
                onPressed: () => onChanged(i.toDouble()),
                icon: LayoutBuilder(
                  builder: (context, box) {
                    final size = box.maxWidth.clamp(24.0, 48.0);
                    return SizedBox(
                      width: size,
                      height: size,
                      child: Stack(
                        children: [
                          Icon(
                            Icons.star_border_rounded,
                            size: size,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          ClipRect(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              widthFactor: ((value ?? 0) - (i - 1))
                                  .clamp(0, 1)
                                  .toDouble(),
                              child: Icon(
                                Icons.star_rounded,
                                size: size,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
