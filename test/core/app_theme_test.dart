import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medlink_connect/core/app_theme.dart';

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = math.max(firstLuminance, secondLuminance);
  final darker = math.min(firstLuminance, secondLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('menus and dialogs use opaque surfaces in both themes', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      expect(theme.colorScheme.surface.a, 1.0);
      expect(theme.canvasColor.a, 1.0);
      expect(theme.dialogTheme.backgroundColor?.a, 1.0);
      expect(theme.popupMenuTheme.color?.a, 1.0);
    }
  });

  test('primary and text colours keep accessible contrast', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      expect(
        _contrastRatio(theme.colorScheme.primary, theme.colorScheme.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(theme.colorScheme.surface, theme.colorScheme.onSurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(
          theme.colorScheme.surface,
          theme.colorScheme.onSurfaceVariant,
        ),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
