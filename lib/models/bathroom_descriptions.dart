import 'package:flutter/material.dart';
import 'package:bath_royale/models/review.dart';
import 'package:bath_royale/theme/custom_color_roles.dart';

extension ReviewDescriptions on Review {
  // Paper description
  String get paperText {
    switch (paperAvailability) {
      case 0:
        return "❌ Sem papel";
      case 1:
        return "🤏🧻 Pouco";
      case 2:
        return "🧻 Suficiente";
      default:
        return "❌ ERRO: quantidade de papel inválida ❌";
    }
  }

  // Hygiene description
  String get hygieneText {
    switch (hygiene) {
      case 0:
        return "💩 Tudo cagado";
      case 1:
        return "🤢 Sujo";
      case 2:
        return "🚽 Ok";
      case 3:
        return "🌸 Limpo";
      case 4:
        return "✨ Um brinco";
      default:
        return "❌ ERRO: higiene inválida ❌";
    }
  }

  // Comfort
  String get comfortText {
    switch (comfort) {
      case 0:
        return "🌿 Cagar no mato";
      case 1:
        return "🪑 Assento básico";
      case 2:
        return "🚽 Funcional";
      case 3:
        return "🌸 Confortável";
      case 4:
        return "🛋️ Poltrona";
      default:
        return "❌ ERRO: conforto inválido ❌";
    }
  }

  // Aesthetics
  String get aestheticText {
    switch (aesthetics) {
      case 0:
        return "🕳️ Caverna";
      case 1:
        return "😬 Feio";
      case 2:
        return "😐 Average";
      case 3:
        return "🌸 Instagramável";
      case 4:
        return "🌈 Scenic piss";
      default:
        return "❌ ERRO: estética inválida ❌";
    }
  }

  // Emoji for rating
  String emojiRating() {
    if (rating >= 4.5) return "🤩";
    if (rating >= 3.5) return "🙂";
    if (rating >= 2.5) return "😐";
    if (rating >= 1.5) return "🤢";
    return "💀";
  }

  // Color for rating
  Color colorRating(BuildContext context) {
    final customColorRoles = Theme.of(context).extension<CustomColorRoles>()!;
    if (rating > 3.5) return customColorRoles.good;
    if (rating > 2.5) return customColorRoles.neutral;
    return customColorRoles.bad;
  }
}
