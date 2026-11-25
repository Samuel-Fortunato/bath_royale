import 'package:bath_royale/theme/custom_color_roles.dart';
import 'package:flutter/material.dart';

class AppTheme {
  static final lightTheme = ThemeData(
    colorSchemeSeed: Colors.brown,
    brightness: Brightness.light,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 0,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
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
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      scrolledUnderElevation: 0,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
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
