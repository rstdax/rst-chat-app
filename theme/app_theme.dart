import 'package:flutter/material.dart';

class RSTAppTheme {
  // RST Brand Colors
  static const Color primaryTeal = Color(0xFF0F766E);
  static const Color darkBackground = Color(0xFF042F2E);

  static ThemeData get glassTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      // 1. Set the primary color
      colorScheme: ColorScheme.dark(
        primary: primaryTeal,
        secondary: Colors.tealAccent,
        surface: Colors.white.withOpacity(
          0.05,
        ), // Default dark transparent surface
      ),
      // 2. Make Scaffold backgrounds completely transparent globally
      scaffoldBackgroundColor: Colors.transparent,
      // 3. Make AppBars transparent and blur-ready
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      // 4. Global Text Styling
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
      ),
    );
  }
}
