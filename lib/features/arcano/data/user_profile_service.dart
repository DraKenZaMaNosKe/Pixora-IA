import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Local-only profile used by ARCANO for personalised lunar / tarot readings.
///
/// **Privacy guarantee**: this data NEVER leaves the device. It lives in a
/// Hive box (`pixora_arcano_profile`) on local storage, no Supabase, no
/// analytics, no telemetry. Even crash reports redact it.
///
/// Singleton + ChangeNotifier — same pattern as CreditService / AuthService
/// elsewhere in Pixora. Use `await UserProfileService.instance.init()` once
/// at app start (already chained by ArcanoPage on first build).
class UserProfileService extends ChangeNotifier {
  UserProfileService._();
  static final instance = UserProfileService._();

  static const _boxName = 'pixora_arcano_profile';
  static const _keyName = 'name';
  static const _keyBirthDay = 'birth_day';
  static const _keyBirthMonth = 'birth_month';
  static const _keyBirthYear = 'birth_year';

  Box? _box;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _box = await Hive.openBox(_boxName);
    _initialized = true;
  }

  bool get isInitialized => _initialized;

  /// True when the user has provided BOTH name and birth date — only then is
  /// the profile considered usable for personalisation. ArcanoPage shows the
  /// onboarding modal whenever this is false.
  bool get hasProfile {
    final box = _box;
    if (box == null) return false;
    final n = box.get(_keyName) as String?;
    final d = box.get(_keyBirthDay) as int?;
    final m = box.get(_keyBirthMonth) as int?;
    final y = box.get(_keyBirthYear) as int?;
    return n != null &&
        n.trim().isNotEmpty &&
        d != null &&
        m != null &&
        y != null;
  }

  String get name => (_box?.get(_keyName) as String?)?.trim() ?? '';
  int? get birthDay => _box?.get(_keyBirthDay) as int?;
  int? get birthMonth => _box?.get(_keyBirthMonth) as int?;
  int? get birthYear => _box?.get(_keyBirthYear) as int?;

  DateTime? get birthDate {
    final d = birthDay;
    final m = birthMonth;
    final y = birthYear;
    if (d == null || m == null || y == null) return null;
    return DateTime(y, m, d);
  }

  /// Persist the profile. Called from the onboarding modal's save button.
  /// Notifies listeners so any open ArcanoPage refreshes immediately.
  Future<void> save({
    required String name,
    required DateTime birthDate,
  }) async {
    final box = _box;
    if (box == null) {
      throw StateError('UserProfileService.init() must be called first');
    }
    await box.putAll({
      _keyName: name.trim(),
      _keyBirthDay: birthDate.day,
      _keyBirthMonth: birthDate.month,
      _keyBirthYear: birthDate.year,
    });
    notifyListeners();
  }

  /// Wipe the profile. Useful for "edit my profile" → re-onboard, or for
  /// privacy concerns ("forget me" button in Settings, future).
  Future<void> clear() async {
    await _box?.clear();
    notifyListeners();
  }

  /// Computed zodiac sign from birth date (Western tropical zodiac, dates
  /// per the standard sun-sign cutoffs used by most almanacs).
  ZodiacSign? get zodiacSign {
    final d = birthDay;
    final m = birthMonth;
    if (d == null || m == null) return null;
    return _zodiacFor(month: m, day: d);
  }

  static ZodiacSign _zodiacFor({required int month, required int day}) {
    // Order matters: each clause checks the START date; if we're past it
    // and before the NEXT sign's start, we're in the current one.
    bool after(int sm, int sd) => month > sm || (month == sm && day >= sd);
    if (after(12, 22)) return ZodiacSign.capricorn; // Dec 22+
    if (after(11, 22)) return ZodiacSign.sagittarius;
    if (after(10, 23)) return ZodiacSign.scorpio;
    if (after(9, 23)) return ZodiacSign.libra;
    if (after(8, 23)) return ZodiacSign.virgo;
    if (after(7, 23)) return ZodiacSign.leo;
    if (after(6, 21)) return ZodiacSign.cancer;
    if (after(5, 21)) return ZodiacSign.gemini;
    if (after(4, 20)) return ZodiacSign.taurus;
    if (after(3, 21)) return ZodiacSign.aries;
    if (after(2, 19)) return ZodiacSign.pisces;
    if (after(1, 20)) return ZodiacSign.aquarius;
    return ZodiacSign.capricorn; // before Jan 20
  }

  /// Pythagorean life-path number — sum birth date digits, reduce to a
  /// single digit (or 11/22/33 master numbers, kept whole).
  int? get lifePath {
    final d = birthDay;
    final m = birthMonth;
    final y = birthYear;
    if (d == null || m == null || y == null) return null;
    int sum = '$d$m$y'.split('').map(int.parse).reduce((a, b) => a + b);
    while (sum > 9 && sum != 11 && sum != 22 && sum != 33) {
      sum = sum.toString().split('').map(int.parse).reduce((a, b) => a + b);
    }
    return sum;
  }

  /// Solfeggio frequency mapped from zodiac. Six core frequencies cycle
  /// through the 12 signs (each pair of opposites shares a frequency).
  int? get personalFrequency {
    final z = zodiacSign;
    if (z == null) return null;
    return switch (z) {
      ZodiacSign.aries || ZodiacSign.libra => 396,
      ZodiacSign.taurus || ZodiacSign.scorpio => 528,
      ZodiacSign.gemini || ZodiacSign.sagittarius => 639,
      ZodiacSign.cancer || ZodiacSign.capricorn => 741,
      ZodiacSign.leo || ZodiacSign.aquarius => 852,
      ZodiacSign.virgo || ZodiacSign.pisces => 963,
    };
  }
}

enum ZodiacSign {
  aries('Aries', '♈'),
  taurus('Tauro', '♉'),
  gemini('Géminis', '♊'),
  cancer('Cáncer', '♋'),
  leo('Leo', '♌'),
  virgo('Virgo', '♍'),
  libra('Libra', '♎'),
  scorpio('Escorpio', '♏'),
  sagittarius('Sagitario', '♐'),
  capricorn('Capricornio', '♑'),
  aquarius('Acuario', '♒'),
  pisces('Piscis', '♓');

  final String label;
  final String glyph;
  const ZodiacSign(this.label, this.glyph);
}
