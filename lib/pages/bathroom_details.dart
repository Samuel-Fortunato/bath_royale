import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/review.dart';
import '../models/bathroom_descriptions.dart';
import '../state/app_state.dart';
import 'review_form.dart';

String reviewDate(DateTime value) {
  final date = value.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(date.day)}/${pad(date.month)}/${date.year} ${pad(date.hour)}:${pad(date.minute)}';
}

class BathroomDetailsPage extends StatelessWidget {
  final String bathroomId;
  const BathroomDetailsPage({super.key, required this.bathroomId});

  @override
  Widget build(BuildContext context) {
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

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
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
            Text(
              '${review.emojiRating()} ${review.rating.toStringAsFixed(1)} / 5',
            ),
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
                children: [
                  for (final tag in review.tags) Chip(label: Text(tag)),
                ],
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
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.bathroom.name),
        actions: [
          IconButton(
            tooltip: entry.activity.isFavorite
                ? 'Remover dos favoritos'
                : 'Adicionar aos favoritos',
            onPressed: () => state.toggleFavorite(bathroomId),
            icon: Icon(
              entry.activity.isFavorite ? Icons.star : Icons.star_border,
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              heading('Comunidade'),
              Text(
                entry.communityRating == null
                    ? 'Ainda sem avaliações'
                    : 'Média: ${entry.communityRating!.toStringAsFixed(1)} / 5',
              ),
              Text(
                '${entry.reviewCount} ${entry.reviewCount == 1 ? 'avaliação' : 'avaliações'}',
              ),
              heading('A tua avaliação mais recente'),
              Text(
                entry.personalReview == null
                    ? 'Ainda não avaliaste esta casa de banho'
                    : '${entry.personalReview!.rating.toStringAsFixed(1)} / 5',
              ),
              heading('As tuas visitas'),
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      entry.activity.lastVisitedAt == null
                          ? Icons.explore_outlined
                          : Icons.check_circle_outline,
                    ),
                  ),
                  title: Text(
                    entry.activity.lastVisitedAt == null
                        ? 'Ainda por visitar'
                        : 'Visita registada',
                  ),
                  subtitle: Text(
                    entry.activity.lastVisitedAt == null
                        ? 'Marca a tua primeira visita a este trono.'
                        : 'Última visita: ${reviewDate(entry.activity.lastVisitedAt!)}',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => openForm(),
                    icon: const Icon(Icons.rate_review),
                    label: const Text('Nova avaliação'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final visit = state.recordVisit(
                        bathroomId,
                        visitedAt: DateTime.now(),
                      );
                      HapticFeedback.lightImpact();
                      final choice = await showModalBottomSheet<String>(
                        context: context,
                        showDragHandle: true,
                        builder: (context) => SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Visita registada! 🚽',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Queres partilhar como foi? A avaliação é totalmente opcional.',
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () =>
                                      Navigator.pop(context, 'review'),
                                  icon: const Icon(Icons.rate_review),
                                  label: const Text('Avaliar esta visita'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Agora não'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, 'undo'),
                                  child: const Text('Desfazer visita'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      if (!context.mounted) return;
                      if (choice == 'review') openForm(null, visit.id);
                      if (choice == 'undo') state.undoVisit(visit.id);
                    },
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Registar visita agora'),
                  ),
                ],
              ),
              heading('O teu histórico de visitas'),
              if (visits.isEmpty) const Text('As tuas visitas aparecem aqui.'),
              for (final visit in visits)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(reviewDate(visit.visitedAt)),
                    subtitle: state.reviewForVisit(visit.id) == null
                        ? null
                        : Text(
                            '${state.reviewForVisit(visit.id)!.emojiRating()} ${state.reviewForVisit(visit.id)!.rating.toStringAsFixed(1)} / 5',
                          ),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: state.reviewForVisit(visit.id) == null
                              ? 'Avaliar visita'
                              : 'Editar avaliação',
                          icon: Icon(
                            state.reviewForVisit(visit.id) == null
                                ? Icons.rate_review_outlined
                                : Icons.edit_outlined,
                          ),
                          onPressed: () => openForm(
                            state.reviewForVisit(visit.id),
                            visit.id,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remover visita',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final hasReview =
                                state.reviewForVisit(visit.id) != null;
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Remover visita?'),
                                content: Text(
                                  hasReview
                                      ? 'A avaliação associada também será removida.'
                                      : 'Esta visita será removida do teu histórico.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancelar'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Remover'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              state.deleteVisit(
                                visit.id,
                                deleteReview: hasReview,
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              heading('Todas as avaliações'),
              if (reviews.isEmpty)
                const Text('Ainda ninguém se sentou para avaliar. 🚽'),
              ...reviews.map(reviewTile),
            ],
          ),
        ),
      ),
    );
  }
}
