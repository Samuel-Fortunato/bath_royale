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
    final mine = reviews
        .where((r) => r.authorId == state.currentUserId)
        .toList();
    void openForm([Review? review]) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChangeNotifierProvider.value(
            value: state,
            child: ReviewFormPage(bathroomId: bathroomId, review: review),
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
                    onPressed: () {
                      final previous = state
                          .activityFor(bathroomId)
                          .lastVisitedAt;
                      final now = DateTime.now();
                      state.recordVisit(bathroomId, visitedAt: now);
                      if (state.activityFor(bathroomId).lastVisitedAt != now) {
                        return;
                      }
                      HapticFeedback.lightImpact();
                      final messenger = ScaffoldMessenger.of(context);
                      messenger.hideCurrentSnackBar();
                      messenger.showSnackBar(
                        SnackBar(
                          content: const Text('Visita registada! 🚽'),
                          action: SnackBarAction(
                            label: 'Desfazer',
                            onPressed: () {
                              state.undoVisit(
                                bathroomId,
                                recordedAt: now,
                                previousAt: previous,
                              );
                            },
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Registar visita agora'),
                  ),
                ],
              ),
              heading('O teu histórico'),
              if (mine.isEmpty)
                const Text('A tua primeira avaliação começa aqui.'),
              ...mine.map(reviewTile),
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
