import 'package:bath_royale/models/bathroom_entry.dart';
import 'package:bath_royale/models/bathroom_descriptions.dart';
import 'package:bath_royale/theme/custom_color_roles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

class WcCard extends StatelessWidget {
  final BathroomEntry entry;
  final VoidCallback toggleFavorite;
  final VoidCallback onTap;

  const WcCard({
    super.key,
    required this.entry,
    required this.toggleFavorite,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bathroom = entry.bathroom;
    final review = entry.personalReview;
    final customColorRoles = Theme.of(context).extension<CustomColorRoles>()!;
    final stateColor = review != null
        ? review.colorRating(context)
        : Theme.of(context).colorScheme.onSurface;

    return Card(
      color: stateColor.withValues(alpha: 0.10),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    review != null ? review.emojiRating() : "🚽",
                    style: TextTheme.of(context).titleLarge,
                  ),
                  // TODO: spacing based on theme ???
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bathroom.name,
                      style: TextTheme.of(context).titleLarge,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: entry.activity.isFavorite
                        ? 'Remover dos favoritos'
                        : 'Adicionar aos favoritos',
                    onPressed: toggleFavorite,
                    icon: Icon(
                      entry.activity.isFavorite
                          ? Icons.star
                          : Icons.star_border,
                      color: customColorRoles.favouriteStar,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entry.communityRating == null
                    ? 'Comunidade: sem avaliações'
                    : 'Comunidade: ${entry.communityRating!.toStringAsFixed(1)} / 5 (${entry.reviewCount})',
              ),
              const Text('A minha última experiência avaliada'),
              if (review == null)
                Text(
                  "Ainda não avaliada",
                  style: TextTheme.of(context).bodyMedium,
                ),
              if (review != null) ...[
                // RATING ROW
                Row(
                  children: [
                    RatingBarIndicator(
                      rating: review.rating,
                      itemCount: 5,
                      itemSize: 18,
                      itemBuilder: (_, _) =>
                          Icon(Icons.star, color: customColorRoles.starRating),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      review.rating.toStringAsFixed(1),
                      style: TextTheme.of(context).bodyMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // CATEGORY QUICK INFO
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    infoSpan("Higiene", review.hygieneText),
                    infoSpan("Conforto", review.comfortText),
                    infoSpan("Estética", review.aestheticText),
                    infoSpan("Papel", review.paperText),
                  ],
                ),
                const SizedBox(height: 10),
                // TAGS
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: review.tags.map((t) {
                    return Chip(
                      label: Text(t),
                      backgroundColor: stateColor.withValues(alpha: 0.25),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// TODO: Rework infoSpan
Widget infoSpan(String label, String value) {
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: "$label: ",
          // TODO: make theme-based
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        TextSpan(text: value),
      ],
    ),
  );
}
