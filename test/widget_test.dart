import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rst_chat_app/main.dart'; // Make sure this matches your project name

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    // Wrap RSTChatApp in ProviderScope for Riverpod
    await tester.pumpWidget(const ProviderScope(child: RSTChatApp()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
