import 'package:bath_royale/theme/custom_color_roles.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static final lightTheme = ThemeData(
    colorSchemeSeed: Colors.brown,
    brightness: Brightness.light,
    extensions: const [
      CustomColorRoles(
        good: Colors.green,
        neutral: Colors.yellow,
        bad: Colors.red,
        starRating: Colors.yellow,
        favouriteStar: Colors.yellow,
      ),
    ],
  );
  static final darkTheme = ThemeData(
    colorSchemeSeed: Colors.brown,
    brightness: Brightness.dark,
    extensions: const [
      CustomColorRoles(
        good: Colors.green,
        neutral: Colors.yellow,
        bad: Colors.red,
        starRating: Colors.yellow,
        favouriteStar: Colors.yellow,
      ),
    ],
  );
}
