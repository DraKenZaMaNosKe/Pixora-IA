import 'package:flutter/material.dart';

enum WallpaperCategory {
  all('All', Icons.apps),
  anime('Anime', Icons.animation),
  gaming('Gaming', Icons.sports_esports),
  nature('Nature', Icons.park),
  animals('Animals', Icons.pets),
  universe('Universe', Icons.rocket_launch),
  scenes('Scenes', Icons.movie),
  horror('Horror', Icons.sentiment_very_dissatisfied),
  abstract_('Abstract', Icons.blur_on),
  minimal('Minimal', Icons.crop_square),
  christmas('Christmas', Icons.ac_unit),
  special('Special', Icons.star);

  const WallpaperCategory(this.label, this.icon);
  final String label;
  final IconData icon;

  static WallpaperCategory fromString(String value) {
    return WallpaperCategory.values.firstWhere(
      (c) => c.name.toUpperCase() == value.toUpperCase() ||
          c.name.replaceAll('_', '').toUpperCase() == value.toUpperCase(),
      orElse: () => WallpaperCategory.all,
    );
  }
}
