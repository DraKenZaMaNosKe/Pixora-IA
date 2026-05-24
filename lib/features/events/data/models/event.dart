import 'package:flutter/material.dart';

/// A seasonal event in Pixora — Mother's Day, Day of the Dead, Christmas, etc.
/// Curated server-side via tools/events/events_catalog.json. Each event has
/// its own theme color, date window, and exclusive wallpaper collection
/// (locked behind Pro subscription when `isProOnly` is true).
class PixoraEvent {
  final String id;
  final String name;
  final String description;
  final String icon; // emoji
  final Color themeColor; // primary
  final Color themeColorDark; // gradient bottom
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isProOnly;
  final List<String> wallpaperIds;
  final int wallpaperCount;
  final List<String> tags;
  final String? bannerUrl;
  final String? memoriaUrl;

  const PixoraEvent({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.themeColor,
    required this.themeColorDark,
    required this.startsAt,
    required this.endsAt,
    this.isProOnly = true,
    this.wallpaperIds = const [],
    this.wallpaperCount = 0,
    this.tags = const [],
    this.bannerUrl,
    this.memoriaUrl,
  });

  /// Lifecycle helpers — UI uses these to pick the polaroid placement
  /// (active = featured big, upcoming = mid row, past = bottom row).
  EventStatus get status {
    final now = DateTime.now().toUtc();
    if (now.isBefore(startsAt)) return EventStatus.upcoming;
    if (now.isAfter(endsAt)) return EventStatus.past;
    return EventStatus.active;
  }

  bool get isActive => status == EventStatus.active;
  bool get isUpcoming => status == EventStatus.upcoming;
  bool get isPast => status == EventStatus.past;

  /// Days remaining until this event starts (>=0) or until it ends if active.
  int get daysUntil {
    final now = DateTime.now().toUtc();
    final target = isActive ? endsAt : startsAt;
    return target.difference(now).inDays.clamp(0, 9999);
  }

  String get monthLabel {
    const months = [
      'ENE',
      'FEB',
      'MAR',
      'ABR',
      'MAY',
      'JUN',
      'JUL',
      'AGO',
      'SEP',
      'OCT',
      'NOV',
      'DIC',
    ];
    return months[startsAt.month - 1];
  }

  String get formattedDateRange {
    final start = startsAt.day;
    final end = endsAt.day;
    final m = monthLabel.toLowerCase();
    if (startsAt.month == endsAt.month) {
      return '$start — $end $m · ${startsAt.year}';
    }
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    final m1 = months[startsAt.month - 1];
    final m2 = months[endsAt.month - 1];
    return '$start $m1 — $end $m2 · ${endsAt.year}';
  }

  factory PixoraEvent.fromJson(Map<String, dynamic> json) {
    Color parseColor(String? hex, [Color fallback = const Color(0xFF888888)]) {
      if (hex == null || !hex.startsWith('#') || hex.length < 7) {
        return fallback;
      }
      try {
        final v = int.parse(hex.substring(1, 7), radix: 16);
        return Color(0xFF000000 | v);
      } catch (_) {
        return fallback;
      }
    }

    return PixoraEvent(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? '🎉',
      themeColor: parseColor(json['theme_color'] as String?),
      themeColorDark: parseColor(json['theme_color_dark'] as String?),
      startsAt: DateTime.parse(json['starts_at'] as String).toUtc(),
      endsAt: DateTime.parse(json['ends_at'] as String).toUtc(),
      isProOnly: json['is_pro_only'] as bool? ?? true,
      wallpaperIds: (json['wallpaper_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      wallpaperCount: (json['wallpaper_count'] as num?)?.toInt() ?? 0,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              const [],
      bannerUrl: json['banner_url'] as String?,
      memoriaUrl: json['memoria_url'] as String?,
    );
  }
}

enum EventStatus { active, upcoming, past }
