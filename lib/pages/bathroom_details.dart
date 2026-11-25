import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/review.dart';
import '../models/visit.dart';
import '../models/ranking.dart';
import '../models/bathroom_descriptions.dart';
import '../state/app_state.dart';
import 'review_form.dart';
import 'experience_details.dart';
import '../widgets/bathroom_identity.dart';

String reviewDate(DateTime value) {
  final date = value.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(date.day)}/${pad(date.month)}/${date.year} ${pad(date.hour)}:${pad(date.minute)}';
}

class BathroomDetailsPage extends StatefulWidget {
  final String bathroomId;
  const BathroomDetailsPage({super.key, required this.bathroomId});

  @override
  State<BathroomDetailsPage> createState() => _BathroomDetailsPageState();
}

class _BathroomDetailsPageState extends State<BathroomDetailsPage> {
  bool _personal = false;
  bool _inviting = false;

  @override
  Widget build(BuildContext context) {
    final bathroomId = widget.bathroomId;
    final state = context.watch<AppState>();
    final entry = state.entries.firstWhere((e) => e.bathroom.id == bathroomId);
    final reviews =
        state.reviews.where((r) => r.bathroomId == bathroomId).toList()
          ..sort((a, b) {
            final order = b.createdAt.compareTo(a.createdAt);
            return order == 0 ? b.id.compareTo(a.id) : order;
          });
    final visits = state.visitsFor(bathroomId);
    void openForm([Review? review, String? visitId]) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChangeNotifierProvider.value(
            value: state,
            child: ReviewFormPage(
              bathroomId: bathroomId,
              review: review,
              visitId: visitId,
            ),
          ),
        ),
      );
    }

    Future<void> registerVisit() async {
      if (_inviting) return;
      setState(() => _inviting = true);
      try {
        final visit = state.recordVisit(bathroomId, visitedAt: DateTime.now());
        HapticFeedback.lightImpact();
        final choice = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (sheetContext) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.pop(sheetContext, 'undo'),
                        icon: const Icon(Icons.undo),
                        label: const Text('Desfazer'),
                      ),
                      IconButton(
                        tooltip: 'Fechar convite',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '🚽 🎉',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 40),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Mais um trono!',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Visita registada com sucesso.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Como foi a experiência?',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, 'review'),
                    child: const Text('Avaliar experiência'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Agora não'),
                  ),
                ],
              ),
            ),
          ),
        );
        if (!context.mounted) return;
        if (choice == 'undo') state.undoVisit(visit.id);
        if (choice == 'review') openForm(null, visit.id);
      } finally {
        if (mounted) setState(() => _inviting = false);
      }
    }

    Widget reviewTile(Review review) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              review.authorId == state.currentUserId
                  ? 'Tu'
                  : 'Explorador ${review.authorId}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('${review.emojiRating()} ${ratingNumber(review.rating)} / 5'),
            Text('Criada: ${reviewDate(review.createdAt)}'),
            if (review.updatedAt != review.createdAt)
              Text('Editada: ${reviewDate(review.updatedAt)}'),
            const SizedBox(height: 8),
            Text(
              'Higiene: ${review.hygieneText}\nConforto: ${review.comfortText}\nEstética: ${review.aestheticText}\nPapel: ${review.paperText}',
            ),
            if (review.tags.isNotEmpty)
              Wrap(
                spacing: 6,
                children: [for (final tag in review.tags) ReviewTag(tag)],
              ),
            if (review.authorId == state.currentUserId)
              TextButton.icon(
                onPressed: () => openForm(review),
                icon: const Icon(Icons.edit),
                label: const Text('Editar avaliação'),
              ),
          ],
        ),
      ),
    );

    void openExperience(String visitId) => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(
          value: state,
          child: ExperienceDetailsPage(visitId: visitId),
        ),
      ),
    );
    Widget visitTile(Visit visit) {
      final review = state.reviewForVisit(visit.id);
      return Card(
        child: ListTile(
          onTap: () => openExperience(visit.id),
          leading: review == null
              ? const Icon(Icons.place_outlined)
              : Text(
                  review.emojiRating(),
                  style: const TextStyle(fontSize: 28),
                ),
          title: Text(
            review == null
                ? 'Visita registada'
                : '${ratingNumber(review.rating)} / 5',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (review != null)
                Text('${review.hygieneText} · ${review.paperText}'),
              Text(
                reviewDate(visit.visitedAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            tooltip: 'Ações da visita',
            onSelected: (action) {
              if (action == 'details') openExperience(visit.id);
              if (action == 'review') openForm(review, visit.id);
              if (action == 'remove') removeExperience(context, state, visit);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'details',
                child: Text('Ver experiência'),
              ),
              PopupMenuItem(
                value: 'review',
                child: Text(
                  review == null ? 'Avaliar visita' : 'Editar avaliação',
                ),
              ),
              const PopupMenuItem(
                value: 'remove',
                child: Text('Remover visita'),
              ),
            ],
          ),
        ),
      );
    }

    final personal = entry.personalReview;
    Widget summary() {
      final empty = _personal ? personal == null : reviews.isEmpty;
      final score = _personal ? personal?.rating : entry.communityRating;
      final categories = RankingMetric.values.skip(1).toList();
      final descriptions = personal == null
          ? <String>[]
          : [
              personal.hygieneText,
              personal.comfortText,
              personal.aestheticText,
              personal.paperText,
            ];
      return ListView(
        key: const PageStorageKey('summary'),
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Comunidade'),
                selected: !_personal,
                onSelected: (_) => setState(() => _personal = false),
              ),
              ChoiceChip(
                label: const Text('A tua experiência'),
                selected: _personal,
                onSelected: (_) => setState(() => _personal = true),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (empty)
            Text(
              _personal
                  ? 'Ainda não avaliaste esta casa de banho'
                  : 'Ainda sem avaliações',
              textAlign: TextAlign.center,
            )
          else ...[
            Icon(Icons.star_rounded, color: ratingGold(context), size: 40),
            Text(
              '${ratingNumber(score!)} / 5',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _personal
                  ? 'Última experiência avaliada · ${reviewDate(state.visits.firstWhere((v) => v.id == personal!.visitId).visitedAt)}'
                  : '${reviews.length} ${reviews.length == 1 ? 'avaliação' : 'avaliações'} da comunidade · média das avaliações locais',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.maxWidth >= 340 &&
                        MediaQuery.textScalerOf(context).scale(14) <= 20
                    ? 2
                    : 1;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < categories.length; i++)
                      SizedBox(
                        width:
                            (constraints.maxWidth - (columns - 1) * 12) /
                            columns,
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CategoryLabel(i, categories[i].label),
                                const SizedBox(height: 8),
                                if (_personal)
                                  Text(
                                    descriptions[i],
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  )
                                else ...[
                                  Text(
                                    '${ratingNumber(reviews.fold<double>(0, (sum, r) => sum + categories[i].score(r)) / reviews.length)} / ${categories[i].maximum}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value:
                                        reviews.fold<double>(
                                          0,
                                          (sum, r) =>
                                              sum + categories[i].score(r),
                                        ) /
                                        reviews.length /
                                        categories[i].maximum,
                                    semanticsLabel: categories[i].label,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (_personal && personal!.tags.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Etiquetas da tua última experiência'),
              Wrap(
                spacing: 8,
                children: [for (final tag in personal.tags) ReviewTag(tag)],
              ),
            ],
          ],
        ],
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              BathroomIdentity(bathroom: entry.bathroom, size: 40),
              const SizedBox(width: 12),
              Expanded(child: Text(entry.bathroom.name, maxLines: 2)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: entry.activity.isFavorite
                  ? 'Remover dos favoritos'
                  : 'Adicionar aos favoritos',
              onPressed: () => state.toggleFavorite(bathroomId),
              icon: Icon(
                entry.activity.isFavorite
                    ? Icons.favorite
                    : Icons.favorite_border,
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _inviting ? null : registerVisit,
                          icon: const Icon(Icons.add_location_alt_outlined),
                          label: const Text('Estive aqui!'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => openForm(),
                          icon: const Icon(Icons.rate_review_outlined),
                          label: const Text('Avaliar'),
                        ),
                      ],
                    ),
                  ),
                  const TabBar(
                    tabs: [
                      Tab(text: 'Resumo'),
                      Tab(text: 'Avaliações'),
                      Tab(text: 'Visitas'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        summary(),
                        reviews.isEmpty
                            ? const Center(
                                child: Text(
                                  'Ainda ninguém se sentou para avaliar. 🚽',
                                ),
                              )
                            : ListView.builder(
                                key: const PageStorageKey('reviews'),
                                padding: const EdgeInsets.all(16),
                                itemCount: reviews.length,
                                itemBuilder: (_, i) => reviewTile(reviews[i]),
                              ),
                        visits.isEmpty
                            ? const Center(
                                child: Text('As tuas visitas aparecem aqui.'),
                              )
                            : ListView.builder(
                                key: const PageStorageKey('visits'),
                                padding: const EdgeInsets.all(16),
                                itemCount: visits.length,
                                itemBuilder: (_, i) => visitTile(visits[i]),
                              ),
                      ],
                    ),
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
