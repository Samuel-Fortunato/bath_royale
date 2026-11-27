import 'package:bath_royale/models/bathroom_entry.dart';
import 'package:bath_royale/models/bathroom_descriptions.dart';
import 'package:flutter/material.dart';
import 'bathroom_identity.dart';

class WcCard extends StatelessWidget {
  final BathroomEntry entry;
  final VoidCallback? toggleFavorite;
  final VoidCallback onTap;

  const WcCard({
    super.key,
    required this.entry,
    required this.toggleFavorite,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final review = entry.personalReview;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  BathroomIdentity(bathroom: entry.bathroom),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.bathroom.name,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: entry.activity.isFavorite
                        ? 'Remover dos favoritos'
                        : 'Adicionar aos favoritos',
                    isSelected: entry.activity.isFavorite,
                    onPressed: toggleFavorite,
                    icon: const Icon(Icons.favorite_border),
                    selectedIcon: const Icon(Icons.favorite),
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
              if (entry.catalogueLabel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    entry.catalogueLabel!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (entry.communityRating == null)
                const Text('Comunidade: sem avaliações')
              else
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '★ ${ratingNumber(entry.communityRating!)} / 5',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: ratingGold(context),
                        ),
                      ),
                      TextSpan(
                        text:
                            ' · ${entry.reviewCount} ${entry.reviewCount == 1 ? 'avaliação' : 'avaliações'} da comunidade',
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  if (review != null)
                    Text(
                      'A tua avaliação: ${ratingNumber(review.rating)} / 5',
                      style: theme.textTheme.bodySmall,
                    ),
                  Text(
                    entry.activity.visitCount > 0
                        ? '✓ Descoberta'
                        : 'Por descobrir',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
