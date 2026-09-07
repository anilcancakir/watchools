// GENERATED: do not edit by hand.
// Regenerate via: dart run magic:artisan design:sync
//
// Source of truth: DESIGN.md

import 'package:flutter/material.dart';

/// Semantic wind alias map generated from DESIGN.md.
///
/// Drop-in for `WindThemeData(aliases: designAliases)`; the
/// keys match the magic_starter token contract.
const Map<String, String> designAliases = <String, String>{
  'bg-surface': 'bg-[#FAFAFB] dark:bg-[#0E0F11]',
  'bg-surface-container': 'bg-[#FFFFFF] dark:bg-[#16181B]',
  'bg-surface-container-high': 'bg-[#F1F3F5] dark:bg-[#1F2226]',
  'text-fg': 'text-[#0E0F11] dark:text-[#F2F4F6]',
  'text-fg-muted': 'text-[#5A6068] dark:text-[#A8AEB6]',
  'text-fg-disabled': 'text-[#B4BAC1] dark:text-[#767D86]',
  'bg-primary': 'bg-[#A36200] dark:bg-[#F59B14]',
  'text-on-primary': 'text-[#FFFFFF] dark:text-[#17181A]',
  'bg-primary-container': 'bg-[#FFF0D6] dark:bg-[#412E10]',
  'bg-accent': 'bg-[#8F5600] dark:bg-[#FAB338]',
  'border-color-border': 'border-[#DFE3E7] dark:border-[#2A2E33]',
  'border-color-border-subtle': 'border-[#EDEFF2] dark:border-[#1A1D20]',
  'bg-destructive': 'bg-[#C42A33] dark:bg-[#F2555F]',
  'text-on-destructive': 'text-[#FFFFFF] dark:text-[#17181A]',
  'bg-destructive-container': 'bg-[#FDE5E7] dark:bg-[#4A1216]',
  'bg-success': 'bg-[#1E8E45] dark:bg-[#3FC46B]',
  'bg-warning': 'bg-[#B77400] dark:bg-[#F0A93A]',
};

/// The brand `primary` color with a generated 50-900 ramp.
///
/// Seeded from the DESIGN.md `primary` light hex; consumed by
/// `WindThemeData.toThemeData()` Material interop.
final Map<String, MaterialColor> designColors = <String, MaterialColor>{
  'primary': MaterialColor(0xFFA36200, <int, Color>{
    50: Color(0xFFF8F2EB),
    100: Color(0xFFF0E6D6),
    200: Color(0xFFE0CAA8),
    300: Color(0xFFCFAD7A),
    400: Color(0xFFBB8B42),
    500: Color(0xFFA36200),
    600: Color(0xFF8F5600),
    700: Color(0xFF7C4A00),
    800: Color(0xFF683F00),
    900: Color(0xFF553300),
  }),
};
