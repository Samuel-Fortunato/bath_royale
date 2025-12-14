import 'package:flutter/material.dart';

class CustomColorRoles extends ThemeExtension<CustomColorRoles> {
  final Color good;
  final Color neutral;
  final Color bad;
  final Color starRating;
  final Color favouriteStar;

  const CustomColorRoles({
    required this.good,
    required this.neutral,
    required this.bad,
    required this.starRating,
    required this.favouriteStar,
  });

  @override
  CustomColorRoles copyWith({
    Color? good,
    Color? neutral,
    Color? bad,
    Color? starRating,
    Color? favouriteStar,
  }) {
    return CustomColorRoles(
      good: good ?? this.good,
      neutral: neutral ?? this.neutral,
      bad: bad ?? this.bad,
      starRating: starRating ?? this.starRating,
      favouriteStar: favouriteStar ?? this.favouriteStar,
    );
  }

  @override
  CustomColorRoles lerp(ThemeExtension<CustomColorRoles>? other, double t) {
    if (other is! CustomColorRoles) return this;
    return CustomColorRoles(
      good: Color.lerp(good, other.good, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      bad: Color.lerp(bad, other.bad, t)!,
      starRating: Color.lerp(starRating, other.starRating, t)!,
      favouriteStar: Color.lerp(favouriteStar, other.favouriteStar, t)!,
    );
  }
}
