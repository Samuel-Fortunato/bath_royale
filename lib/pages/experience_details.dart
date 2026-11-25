import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/visit.dart';
import '../models/bathroom_descriptions.dart';
import '../state/app_state.dart';
import '../widgets/bathroom_identity.dart';
import 'bathroom_details.dart' show reviewDate;
import 'review_form.dart';

Future<bool> removeExperience(
  BuildContext context,
  AppState state,
  Visit visit,
) async {
  final hasReview = state.reviewForVisit(visit.id) != null;
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
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remover'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  state.deleteVisit(visit.id, deleteReview: hasReview);
  return true;
}

/// Represents exactly one visit, including an optional review, for future diary reuse.
class ExperienceDetailsPage extends StatelessWidget {
  final String visitId;
  const ExperienceDetailsPage({super.key, required this.visitId});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final matches = state.visits.where((v) => v.id == visitId);
    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Esta visita foi removida.')),
      );
    }
    final visit = matches.single;
    final bathroom = state.allBathrooms.firstWhere(
      (b) => b.id == visit.bathroomId,
    );
    final review = state.reviewForVisit(visitId);
    final own = visit.userId == state.currentUserId;
    return Scaffold(
      appBar: AppBar(title: const Text('Experiência')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  BathroomIdentity(bathroom: bathroom, size: 64),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      bathroom.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                reviewDate(visit.visitedAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              if (review == null)
                const ListTile(
                  leading: Icon(Icons.place_outlined),
                  title: Text('Visita registada'),
                )
              else ...[
                Text(
                  '${review.emojiRating()} ${ratingNumber(review.rating)} / 5',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 16),
                for (final item in [
                  (0, 'Higiene', review.hygieneText),
                  (1, 'Conforto', review.comfortText),
                  (2, 'Estética', review.aestheticText),
                  (3, 'Papel', review.paperText),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CategoryLabel(item.$1, item.$2),
                        Text(
                          item.$3,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [for (final tag in review.tags) ReviewTag(tag)],
                ),
              ],
              if (own) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.rate_review_outlined),
                  label: Text(
                    review == null ? 'Avaliar visita' : 'Editar avaliação',
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ChangeNotifierProvider.value(
                        value: state,
                        child: ReviewFormPage(
                          bathroomId: bathroom.id,
                          visitId: visit.id,
                          review: review,
                        ),
                      ),
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remover visita'),
                  onPressed: () async {
                    if (await removeExperience(context, state, visit) &&
                        context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
