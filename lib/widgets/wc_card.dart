import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/bathroom_descriptions.dart';
import 'package:bath_royale/theme/custom_color_roles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

class WcCard extends StatelessWidget {
  final Bathroom bathroom;
  final VoidCallback onTap;
  // final VoidCallback toggleFavorite;

  const WcCard({
    super.key,
    required this.bathroom,
    required this.onTap,
    // required this.toggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final customColorRoles = Theme.of(context).extension<CustomColorRoles>()!;
    final stateColor = bathroom.colorRating(context);

    // TODO: Not evaluated bathroom Card
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
                    bathroom.emojiRating(),
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
                  ValueListenableBuilder(
                    valueListenable: bathroom.isFavorite,
                    builder: (context, isFav, _) {
                      return IconButton(
                        onPressed: bathroom.toggleFavorite,
                        icon: Icon(
                          isFav ? Icons.star : Icons.star_border,
                          color: customColorRoles.favouriteStar,
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // RATING ROW
              Row(
                children: [
                  RatingBarIndicator(
                    rating: bathroom.rating,
                    itemCount: 5,
                    itemSize: 18,
                    itemBuilder: (_, _) =>
                        Icon(Icons.star, color: customColorRoles.starRating),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    bathroom.rating.toStringAsFixed(1),
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
                  infoSpan("Higiene", bathroom.hygieneText),
                  infoSpan("Confort", bathroom.confortText),
                  infoSpan("Aesthetics", bathroom.aestheticText),
                  infoSpan("Papel", bathroom.paperText),
                ],
              ),
              const SizedBox(height: 10),
              // TAGS
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: bathroom.tags.map((t) {
                  return Chip(
                    label: Text(t),
                    backgroundColor: stateColor.withValues(alpha: 0.25),
                  );
                }).toList(),
              ),
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
