/// How a category looks: its colour and icon, from the strings the API stores.
///
/// The backend keeps a category's colour as `#RRGGBB` and its icon as a Material icon *name*
/// (`restaurant`, `directions_bus`), so any client can render them. Unknown names fall back to a
/// neutral icon rather than failing, because a user-created category may carry any string.
library;

import 'package:flutter/material.dart';

const Color fallbackCategoryColor = Color(0xFF607D8B);

/// Parse `#RRGGBB` (or `RRGGBB`); anything else gives [fallbackCategoryColor].
Color categoryColor(String? hex) {
  final value = (hex ?? '').replaceFirst('#', '').trim();
  if (value.length != 6) return fallbackCategoryColor;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? fallbackCategoryColor : Color(0xFF000000 | parsed);
}

const Map<String, IconData> _icons = {
  'restaurant': Icons.restaurant_rounded,
  'directions_bus': Icons.directions_bus_rounded,
  'home': Icons.home_rounded,
  'bolt': Icons.bolt_rounded,
  'local_hospital': Icons.local_hospital_rounded,
  'school': Icons.school_rounded,
  'wifi': Icons.wifi_rounded,
  'checkroom': Icons.checkroom_rounded,
  'savings': Icons.savings_rounded,
  'more_horiz': Icons.more_horiz_rounded,
  'coffee': Icons.coffee_rounded,
  'shopping_cart': Icons.shopping_cart_rounded,
  'favorite': Icons.favorite_rounded,
  'phone': Icons.phone_rounded,
  'celebration': Icons.celebration_rounded,
  'church': Icons.church_rounded,
  'child_care': Icons.child_care_rounded,
  'pets': Icons.pets_rounded,
  'local_gas_station': Icons.local_gas_station_rounded,
};

/// The icon names offered when creating or editing a category, in picker order.
List<String> get categoryIconNames => _icons.keys.toList(growable: false);

/// Colours offered in the category editor: the defaults' colours plus a few more, all `#RRGGBB`.
const categoryPalette = [
  '#E53935', '#FB8C00', '#FDD835', '#43A047', '#00897B', '#00ACC1',
  '#1E88E5', '#3949AB', '#8E24AA', '#D81B60', '#6D4C41', '#607D8B',
];

IconData categoryIcon(String? name) => _icons[name?.trim()] ?? Icons.category_rounded;
