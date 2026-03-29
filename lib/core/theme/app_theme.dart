import 'package:flutter/material.dart';

class RSTAppTheme {
  // Google Chat inspired palette
  static const Color primaryBlue = Color(0xFF0A56D0);
  static const Color surfaceVariant = Color(
    0xFFF0F4F9,
  ); // Light grayish-blue for search bars
  static const Color backgroundColor = Colors.white;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.light,
        background: backgroundColor,
        surface: backgroundColor,
        surfaceVariant: surfaceVariant,
      ),
      scaffoldBackgroundColor: backgroundColor,

      // Clean, flat AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
        surfaceTintColor:
            Colors.transparent, // Prevents it from turning grey when scrolling
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.black87),
        titleTextStyle: TextStyle(
          color: Colors.black87,
          fontSize: 22,
          fontWeight: FontWeight.w400,
        ),
      ),

      // Pill-shaped Search Bar Theme
      searchBarTheme: SearchBarThemeData(
        backgroundColor: MaterialStateProperty.all(surfaceVariant),
        elevation: MaterialStateProperty.all(0),
        shape: MaterialStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        ),
      ),

      // Modern Floating Action Button (like the '+' in your screenshot)
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: const Color(0xFFC2E7FF), // Soft light blue
        foregroundColor: const Color(0xFF001D35), // Dark blue icon
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Bottom Navigation Bar
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceVariant,
        indicatorColor: const Color(0xFFC2E7FF),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      ),

      // Clean Text Styling
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.black87, fontSize: 16),
        bodyMedium: TextStyle(
          color: Colors.black54,
          fontSize: 14,
        ), // Used for subtitles
      ),

      // Clean dividers like in the screenshot
      dividerTheme: DividerThemeData(
        color: Colors.grey.withOpacity(0.2),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
