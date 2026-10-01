import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livs/utils/app_theme.dart';

void main() {
  testWidgets('Theme and UI test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: Text('INDOOR POSITIONING'),
        ),
      ),
    );

    expect(find.text('INDOOR POSITIONING'), findsOneWidget);
    expect(AppColors.primaryBg, const Color(0xFF111111));
    expect(AppColors.surface, const Color(0xFF1B1B1B));
    expect(AppColors.primaryAccent, const Color(0xFFFF8A3D));
    expect(AppColors.secondaryAccent, const Color(0xFFF2C14E));
    expect(AppColors.textPrimary, const Color(0xFFF5F5F5));
    expect(AppColors.textSecondary, const Color(0xFF9CA3AF));
    expect(AppColors.border, const Color(0xFF2E2E2E));
  });
}
