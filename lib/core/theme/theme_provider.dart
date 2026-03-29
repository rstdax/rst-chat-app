import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Your existing dark mode provider
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

// ---> NEW: Holds the active app color (Defaults to Teal)
final themeColorProvider = StateProvider<Color>(
  (ref) => const Color(0xFF0F766E),
);

// Helper to convert Color to Hex string for Firestore
String colorToHex(Color color) =>
    '#${color.value.toRadixString(16).substring(2).padLeft(6, '0')}';

// Helper to convert Hex string from Firestore back to Color
Color hexToColor(String hexString) {
  final buffer = StringBuffer();
  if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
  buffer.write(hexString.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}
