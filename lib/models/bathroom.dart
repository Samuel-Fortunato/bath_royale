import 'package:flutter/material.dart';

class Bathroom {
  final String id;
  final String name;
  final ValueNotifier<bool> isFavorite = ValueNotifier(false);
  bool reviewed;

  double rating; // 0-5
  int paperAvailability; // [0,2] 0-não 1-pouco 2-suficiente
  int hygiene; // [0,4] 0-tudo cagado 1-sujo 2-ok 3-limpo 4-um brinco
  int
  confort; // [0,2] 0-cagar no mato 1-assento básico 2-funcional 3-confortável 4-poltrona
  int
  aesthetics; // [0,4] 0-caverna 1-feio 2-average 3-instragamavel 4-scenic piss

  List<String> tags;
  DateTime? lastReviewed;

  Bathroom({
    required this.id,
    required this.name,
    // this.isFavorite = false,
    this.reviewed = false,
    this.rating = 0.0,
    this.paperAvailability = 0,
    this.hygiene = 0,
    this.confort = 0,
    this.aesthetics = 0,
    this.tags = const [],
    this.lastReviewed,
  });

  Bathroom copyWith({
    String? id,
    String? name,
    // bool? isFavorite,
    bool? reviewed,
    double? rating,
    int? paperAvailability,
    int? hygiene,
    int? confort,
    int? aesthetics,
    List<String>? tags,
    DateTime? lastReviewed,
  }) {
    return Bathroom(
      id: id ?? this.id,
      name: name ?? this.name,
      // isFavorite: isFavorite ?? this.isFavorite,
      reviewed: reviewed ?? this.reviewed,
      rating: rating ?? this.rating,
      paperAvailability: paperAvailability ?? this.paperAvailability,
      hygiene: hygiene ?? this.hygiene,
      confort: confort ?? this.confort,
      aesthetics: aesthetics ?? this.aesthetics,
      tags: tags ?? this.tags,
      lastReviewed: lastReviewed ?? this.lastReviewed,
    );
  }

  void toggleFavorite() {
    isFavorite.value = !isFavorite.value;
  }

  void evaluate({
    required double rating,
    required bool paperAvailable,
    required double hygiene,
    required double confort,
    required double aesthetics,
    required List<String> tags,
  }) {
    reviewed = true;
    rating = rating;
    paperAvailable = paperAvailable;
    hygiene = hygiene;
    confort = confort;
    aesthetics = aesthetics;
    tags = tags;
    lastReviewed = DateTime.now();
  }
}
