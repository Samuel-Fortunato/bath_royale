import 'package:flutter/material.dart';

import 'package:bath_royale/models/bathroom.dart';

List<Bathroom> createSampleBathrooms() => [
  Bathroom(
    id: "0",
    name: "DEM - 3º piso",
    rating: 4.7,
    paperAvailability: 2,
    hygiene: 4,
    confort: 4,
    aesthetics: 1,
    tags: ["nice", "cozy", "dark"],
    // isFavorite: true,
    reviewed: true,
    lastReviewed: DateTime.now(),
  ),
  Bathroom(
    id: "1",
    name: "CP - Rés do Chão",
    rating: 1.3,
    paperAvailability: 1,
    hygiene: 2,
    confort: 0,
    aesthetics: 1,
    tags: ["grafiti", "wtf", "no like"],
    // isFavorite: false,
    reviewed: true,
    lastReviewed: DateTime.now(),
  ),
  Bathroom(
    id: "2",
    name: "CP - 2º Piso",
    rating: 4.1,
    paperAvailability: 0,
    hygiene: 3,
    confort: 2,
    aesthetics: 4,
    tags: ["nice", "small", "great view"],
    // isFavorite: true,
    reviewed: true,
    lastReviewed: DateTime.now(),
  ),
  Bathroom(
    id: "3",
    name: "Biblioteca",
    rating: 3,
    paperAvailability: 2,
    hygiene: 1,
    confort: 2,
    aesthetics: 1,
    tags: ["cozy", "sad but true", "noisy"],
    // isFavorite: false,
    reviewed: true,
    lastReviewed: DateTime.now(),
  ),
  Bathroom(
    id: "4",
    name: "CP - 3º Piso",
    rating: 4.1,
    paperAvailability: 2,
    hygiene: 3,
    confort: 2,
    aesthetics: 4,
    tags: ["nice", "small", "great view"],
    // isFavorite: true,
    reviewed: true,
    lastReviewed: DateTime.now(),
  ),
  Bathroom(id: "5", name: "Nome de Teste"),
];

class AppState extends ChangeNotifier {
  bool darkMode = true;
  void toggleTheme() {
    darkMode = !darkMode;
    notifyListeners();
  }

  AppState() : allBathrooms = createSampleBathrooms() {
    for (final bathroom in allBathrooms) {
      bathroom.isFavorite.addListener(notifyListeners);
    }
  }

  final List<Bathroom> allBathrooms;

  @override
  void dispose() {
    for (final bathroom in allBathrooms) {
      bathroom.isFavorite.removeListener(notifyListeners);
      bathroom.isFavorite.dispose();
    }
    super.dispose();
  }
}
