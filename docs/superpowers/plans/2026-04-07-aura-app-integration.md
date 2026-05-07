# AURA App Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new "AURA" tab to Pixora that streams the wellness audio catalog produced by Plan 1, with a full-screen player (play/pause/loop/sleep timer), bilingual ES/EN descriptions, alternating ads + diamond rewards consistent with the rest of the app, and background playback that survives app closure.

**Architecture:** New `lib/features/aura/` feature module following the existing `feature/data | presentation | providers` pattern. A singleton `AuraPlayerService` wraps `just_audio` + `just_audio_background` so playback continues with the app closed (foreground notification with controls). An `AuraRepository` queries the `aura_tracks` table directly via `supabase_flutter`. UI is two segmented lists (Frequencies / Nature) → full-screen player with sleep timer and bilingual description card. Tab inserted into the existing `BottomNavigationBar` in `home_page.dart` after LIVE.

**Tech Stack:** Flutter, Riverpod (already in app), `just_audio` 0.9.40 (already in deps), `just_audio_background` (NEW dep), `supabase_flutter` (already in deps), Hive (for "downloaded for offline" cache), existing `AdService` + `CreditService` singletons.

**Reuses without re-implementing:**
- `AdService.instance.showInterstitialAd(onAdDismissed:)` — already alternates 1-yes/2-no and awards credits internally
- `CreditService.instance.earnFromAd()` — auto-called by AdService
- `WallpaperStatsService.instance.trackView/trackDownload` — for stats badges, same pattern as ringtones
- `lib/features/ringtones/presentation/pages/ringtone_pack_page.dart` — reference implementation for `just_audio` usage in this codebase

---

## File Structure

New files:
- `lib/features/aura/data/models/aura_track.dart` — model + `fromJson`
- `lib/features/aura/data/repositories/aura_repository.dart` — Supabase fetch + 6h cache
- `lib/features/aura/services/aura_player_service.dart` — singleton wrapper around `just_audio` (play/pause/stop/loop/sleep timer/notification)
- `lib/features/aura/providers/aura_providers.dart` — Riverpod providers for catalog + player state
- `lib/features/aura/presentation/pages/aura_page.dart` — main tab page (segmented Frequencies/Nature, grid of cards)
- `lib/features/aura/presentation/pages/aura_player_page.dart` — full-screen player
- `lib/features/aura/presentation/widgets/aura_track_card.dart` — card for each track in the grid
- `lib/features/aura/presentation/widgets/sleep_timer_sheet.dart` — bottom sheet to pick sleep duration
- `lib/core/utils/locale_helper.dart` — tiny helper: `bool get isSpanish => Platform.localeName.toLowerCase().startsWith('es');`

Modified files:
- `pubspec.yaml` — add `just_audio_background: ^0.0.1-beta.13` and `audio_session: ^0.1.21`
- `lib/main.dart` — call `JustAudioBackground.init(...)` before `runApp`
- `lib/features/home/presentation/home_page.dart` — insert AURA into `_pages`, `_title`, and `BottomNavigationBar.items`
- `android/app/src/main/AndroidManifest.xml` — add foreground audio service + notification icon
- `android/app/src/main/res/drawable/ic_aura_notification.xml` — small lotus drawable for the media notification

---

## Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the deps**

In `pubspec.yaml`, under the existing `dependencies:` block (next to the line `just_audio: ^0.9.40`), add:

```yaml
  just_audio_background: ^0.0.1-beta.13
  audio_session: ^0.1.21
```

- [ ] **Step 2: Install**

```bash
flutter pub get
```

Expected: `Got dependencies!` with no version conflicts. If `just_audio_background` resolves to a higher beta, accept it as long as it's compatible with `just_audio: ^0.9.40` (the package README lists supported pairs).

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat(aura): add just_audio_background + audio_session deps"
```

---

## Task 2: AndroidManifest — foreground audio service

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add the permissions and service**

Open `android/app/src/main/AndroidManifest.xml`. Inside the `<manifest>` element (top level, next to existing permissions), ensure these are present (add any that are missing — do NOT duplicate):

```xml
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

Inside `<application>`, add (do NOT remove anything else):

```xml
        <service
            android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService"/>
            </intent-filter>
        </service>

        <receiver
            android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON"/>
            </intent-filter>
        </receiver>
```

- [ ] **Step 2: Add the lotus notification icon**

Create `android/app/src/main/res/drawable/ic_aura_notification.xml`:
```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M12,2C9,5 9,9 12,12C15,9 15,5 12,2zM6,8C4,11 5,15 9,16C9,12 8,9 6,8zM18,8C16,9 15,12 15,16C19,15 20,11 18,8zM3,14C3,17 6,19 9,18C7,16 5,15 3,14zM21,14C19,15 17,16 15,18C18,19 21,17 21,14zM12,14C10,17 11,20 12,22C13,20 14,17 12,14z"/>
</vector>
```

- [ ] **Step 3: Smoke build**

```bash
flutter build apk --debug
```

Expected: build succeeds. If it fails on manifest merge, read the error — usually it's a duplicate `<uses-permission>` that needs to be removed from the additions above.

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml android/app/src/main/res/drawable/ic_aura_notification.xml
git commit -m "feat(aura): manifest permissions + foreground audio service + lotus icon"
```

---

## Task 3: Initialize background audio in main.dart

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add the init call**

At the top of `lib/main.dart`, add the import next to the others:
```dart
import 'package:just_audio_background/just_audio_background.dart';
```

In `main()`, after `await Supabase.initialize(...)` and before `await CreditService.instance.init();`, add:

```dart
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.orbix.pixora.aura.channel.audio',
      androidNotificationChannelName: 'AURA Audio',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'drawable/ic_aura_notification',
    );
```

- [ ] **Step 2: Verify build still passes**

```bash
flutter analyze lib/main.dart
flutter build apk --debug
```

Expected: no analyzer errors, build succeeds.

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat(aura): init JustAudioBackground in main.dart"
```

---

## Task 4: Locale helper

**Files:**
- Create: `lib/core/utils/locale_helper.dart`

- [ ] **Step 1: Write the helper**

Create `lib/core/utils/locale_helper.dart`:
```dart
import 'dart:io';
import 'package:flutter/widgets.dart';

/// Tiny helper for picking ES vs EN strings without a full l10n setup.
/// Reads the device locale via `Platform.localeName` (e.g. "es_MX", "en_US").
class LocaleHelper {
  LocaleHelper._();

  static bool get isSpanish {
    final name = Platform.localeName.toLowerCase();
    return name.startsWith('es');
  }

  /// Convenience: pick es/en string based on current locale.
  static String pick({required String es, required String en}) =>
      isSpanish ? es : en;

  /// Override the locale based on a Flutter `BuildContext` (more accurate
  /// when the app sets `MaterialApp.locale` explicitly). Falls back to the OS.
  static bool isSpanishContext(BuildContext context) {
    final l = Localizations.maybeLocaleOf(context);
    if (l != null) return l.languageCode == 'es';
    return isSpanish;
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/utils/locale_helper.dart
git commit -m "feat(core): add LocaleHelper for ES/EN string picking"
```

---

## Task 5: AuraTrack model

**Files:**
- Create: `lib/features/aura/data/models/aura_track.dart`

- [ ] **Step 1: Write the model**

Create `lib/features/aura/data/models/aura_track.dart`:
```dart
import '../../../../core/utils/locale_helper.dart';

enum AuraCategory { frequency, nature }

class AuraTrack {
  final String id;
  final AuraCategory category;
  final int? hz;              // frequencies only
  final String? chakra;       // frequencies only
  final String? colorHex;     // frequencies only
  final String? icon;         // nature only ('rain','wave',...)
  final String nameEn;
  final String nameEs;
  final String descEn;
  final String descEs;
  final int durationSec;
  final String audioUrl;
  final String license;
  final String? freesoundUser;
  final int sortOrder;

  const AuraTrack({
    required this.id,
    required this.category,
    required this.hz,
    required this.chakra,
    required this.colorHex,
    required this.icon,
    required this.nameEn,
    required this.nameEs,
    required this.descEn,
    required this.descEs,
    required this.durationSec,
    required this.audioUrl,
    required this.license,
    required this.freesoundUser,
    required this.sortOrder,
  });

  String get displayName => LocaleHelper.isSpanish ? nameEs : nameEn;
  String get displayDescription => LocaleHelper.isSpanish ? descEs : descEn;

  factory AuraTrack.fromJson(Map<String, dynamic> json) {
    return AuraTrack(
      id: json['id'] as String,
      category: (json['category'] as String) == 'frequency'
          ? AuraCategory.frequency
          : AuraCategory.nature,
      hz: json['hz'] as int?,
      chakra: json['chakra'] as String?,
      colorHex: json['color_hex'] as String?,
      icon: json['icon'] as String?,
      nameEn: json['name_en'] as String,
      nameEs: json['name_es'] as String,
      descEn: json['desc_en'] as String,
      descEs: json['desc_es'] as String,
      durationSec: json['duration_sec'] as int,
      audioUrl: json['audio_url'] as String,
      license: json['license'] as String? ?? 'CC0',
      freesoundUser: json['freesound_user'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/aura/data/models/aura_track.dart
git commit -m "feat(aura): add AuraTrack model"
```

---

## Task 6: AuraRepository (Supabase fetch + cache)

**Files:**
- Create: `lib/features/aura/data/repositories/aura_repository.dart`

- [ ] **Step 1: Write the repository**

Create `lib/features/aura/data/repositories/aura_repository.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/aura_track.dart';

/// Fetches the AURA catalog from the `public.aura_tracks` Supabase table.
/// 6-hour in-memory cache, matching the pattern used by other catalog services
/// in this codebase (see live_wallpaper_catalog_service.dart).
class AuraRepository {
  AuraRepository._();
  static final instance = AuraRepository._();

  List<AuraTrack>? _cache;
  DateTime? _lastFetch;
  static const _cacheHours = 6;

  Future<List<AuraTrack>> fetchCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cache != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!).inHours < _cacheHours) {
      return _cache!;
    }

    try {
      final rows = await Supabase.instance.client
          .from('aura_tracks')
          .select()
          .order('category')
          .order('sort_order');

      final tracks = (rows as List<dynamic>)
          .map((e) => AuraTrack.fromJson(e as Map<String, dynamic>))
          .toList();
      _cache = tracks;
      _lastFetch = DateTime.now();
      return tracks;
    } catch (e) {
      debugPrint('[Pixora] AURA catalog fetch failed: $e');
      return _cache ?? [];
    }
  }

  List<AuraTrack> filterFrequencies(List<AuraTrack> all) =>
      all.where((t) => t.category == AuraCategory.frequency).toList();

  List<AuraTrack> filterNature(List<AuraTrack> all) =>
      all.where((t) => t.category == AuraCategory.nature).toList();
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/aura/data/repositories/aura_repository.dart
git commit -m "feat(aura): add AuraRepository (Supabase + 6h cache)"
```

---

## Task 7: AuraPlayerService (singleton wrapper around just_audio)

**Files:**
- Create: `lib/features/aura/services/aura_player_service.dart`

This service is the single source of truth for what's currently playing. It exposes streams the UI listens to and methods the UI calls. Sleep timer and loop are handled here, not in the page widgets — so the player keeps working when the user navigates away.

- [ ] **Step 1: Write the service**

Create `lib/features/aura/services/aura_player_service.dart`:
```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../data/models/aura_track.dart';

class AuraPlayerService extends ChangeNotifier {
  AuraPlayerService._();
  static final instance = AuraPlayerService._();

  final AudioPlayer _player = AudioPlayer();
  AuraTrack? _current;
  bool _loop = true;
  Timer? _sleepTimer;
  DateTime? _sleepEndsAt;

  AuraTrack? get current => _current;
  bool get loop => _loop;
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  DateTime? get sleepEndsAt => _sleepEndsAt;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> init() async {
    // Default to single-track loop. We'll re-set on each track change too.
    await _player.setLoopMode(LoopMode.one);
    _player.playerStateStream.listen((_) => notifyListeners());
  }

  Future<void> play(AuraTrack track) async {
    _current = track;
    notifyListeners();
    try {
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(track.audioUrl),
          tag: MediaItem(
            id: track.id,
            title: track.displayName,
            album: track.category == AuraCategory.frequency ? 'Frequencies' : 'Nature',
            artist: 'Pixora · AURA',
            duration: Duration(seconds: track.durationSec),
          ),
        ),
      );
      await _player.setLoopMode(_loop ? LoopMode.one : LoopMode.off);
      await _player.play();
    } catch (e) {
      debugPrint('[Pixora] AURA play failed: $e');
    }
  }

  Future<void> pause() async { await _player.pause(); }
  Future<void> resume() async { await _player.play(); }

  Future<void> stop() async {
    await _player.stop();
    _current = null;
    _cancelSleepTimer();
    notifyListeners();
  }

  Future<void> seek(Duration position) async => _player.seek(position);

  Future<void> setLoop(bool value) async {
    _loop = value;
    await _player.setLoopMode(value ? LoopMode.one : LoopMode.off);
    notifyListeners();
  }

  // ── Sleep timer ────────────────────────────────────────────────────

  void startSleepTimer(Duration d) {
    _cancelSleepTimer();
    _sleepEndsAt = DateTime.now().add(d);
    _sleepTimer = Timer(d, () async {
      // Soft fade-out then stop
      for (var v = _player.volume; v > 0; v -= 0.05) {
        await _player.setVolume(v.clamp(0.0, 1.0));
        await Future.delayed(const Duration(milliseconds: 100));
      }
      await _player.stop();
      await _player.setVolume(1.0);
      _current = null;
      _sleepEndsAt = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepEndsAt = null;
  }

  void cancelSleepTimer() {
    _cancelSleepTimer();
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelSleepTimer();
    _player.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 2: Wire init in main.dart**

In `lib/main.dart`, after `await CreditService.instance.init();`, add:
```dart
    await AuraPlayerService.instance.init();
```

And add the import at the top:
```dart
import 'features/aura/services/aura_player_service.dart';
```

- [ ] **Step 3: Verify build**

```bash
flutter analyze lib/features/aura lib/main.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/aura/services/aura_player_service.dart lib/main.dart
git commit -m "feat(aura): add AuraPlayerService with sleep timer and background playback"
```

---

## Task 8: Riverpod providers

**Files:**
- Create: `lib/features/aura/providers/aura_providers.dart`

- [ ] **Step 1: Write providers**

Create `lib/features/aura/providers/aura_providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/aura_track.dart';
import '../data/repositories/aura_repository.dart';

final auraCatalogProvider = FutureProvider<List<AuraTrack>>((ref) async {
  return AuraRepository.instance.fetchCatalog();
});

final auraFrequenciesProvider = Provider<AsyncValue<List<AuraTrack>>>((ref) {
  final all = ref.watch(auraCatalogProvider);
  return all.whenData(AuraRepository.instance.filterFrequencies);
});

final auraNatureProvider = Provider<AsyncValue<List<AuraTrack>>>((ref) {
  final all = ref.watch(auraCatalogProvider);
  return all.whenData(AuraRepository.instance.filterNature);
});
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/aura/providers/aura_providers.dart
git commit -m "feat(aura): add Riverpod providers for catalog"
```

---

## Task 9: AuraTrackCard widget

**Files:**
- Create: `lib/features/aura/presentation/widgets/aura_track_card.dart`

- [ ] **Step 1: Write the card**

Create `lib/features/aura/presentation/widgets/aura_track_card.dart`:
```dart
import 'package:flutter/material.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../wallpapers/presentation/widgets/wallpaper_stats_bar.dart';
import '../../data/models/aura_track.dart';

class AuraTrackCard extends StatelessWidget {
  final AuraTrack track;
  final bool isPlaying;
  final VoidCallback onTap;

  const AuraTrackCard({
    super.key,
    required this.track,
    required this.isPlaying,
    required this.onTap,
  });

  Color get _accent {
    if (track.colorHex != null) {
      return parseHexColor(track.colorHex!, fallback: const Color(0xFF7C4DFF));
    }
    return const Color(0xFF7C4DFF);
  }

  IconData get _natureIcon {
    switch (track.icon) {
      case 'rain':       return Icons.grain;
      case 'storm':      return Icons.thunderstorm;
      case 'wave':       return Icons.waves;
      case 'river':      return Icons.water;
      case 'waterfall':  return Icons.water_drop;
      case 'fire':       return Icons.local_fire_department;
      case 'forest':     return Icons.forest;
      case 'wind':       return Icons.air;
      case 'lightning':  return Icons.flash_on;
      case 'moon':       return Icons.nightlight_round;
      case 'coffee':     return Icons.local_cafe;
      case 'static':     return Icons.graphic_eq;
      case 'bowl':       return Icons.spa;
      case 'bell':       return Icons.notifications_none;
      default:           return Icons.music_note;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFreq = track.category == AuraCategory.frequency;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _accent.withOpacity(0.45),
              _accent.withOpacity(0.10),
            ],
          ),
          border: Border.all(
            color: isPlaying ? _accent : Colors.white.withOpacity(0.08),
            width: isPlaying ? 2 : 1,
          ),
          boxShadow: isPlaying
              ? [BoxShadow(color: _accent.withOpacity(0.5), blurRadius: 18, spreadRadius: 1)]
              : [BoxShadow(color: _accent.withOpacity(0.12), blurRadius: 8)],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Stats
            Positioned(
              top: 8, right: 8,
              child: WallpaperStatsBar(
                wallpaperId: 'aura_${track.id}',
                glowColor: _accent,
              ),
            ),
            // Center icon / Hz label
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isFreq ? Icons.graphic_eq : _natureIcon,
                    size: 38,
                    color: Colors.white.withOpacity(0.95),
                  ),
                  if (isFreq) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${track.hz} Hz',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Bottom name
            Positioned(
              left: 10, right: 10, bottom: 10,
              child: Text(
                track.displayName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Now playing indicator
            if (isPlaying)
              Positioned(
                top: 8, left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow, size: 11, color: Colors.white),
                      SizedBox(width: 2),
                      Text('NOW',
                        style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/aura/presentation/widgets/aura_track_card.dart
git commit -m "feat(aura): add AuraTrackCard widget"
```

---

## Task 10: AuraPage (segmented Frequencies / Nature)

**Files:**
- Create: `lib/features/aura/presentation/pages/aura_page.dart`

- [ ] **Step 1: Write the page**

Create `lib/features/aura/presentation/pages/aura_page.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../data/models/aura_track.dart';
import '../../providers/aura_providers.dart';
import '../../services/aura_player_service.dart';
import '../widgets/aura_track_card.dart';
import 'aura_player_page.dart';

class AuraPage extends ConsumerStatefulWidget {
  const AuraPage({super.key});

  @override
  ConsumerState<AuraPage> createState() => _AuraPageState();
}

class _AuraPageState extends ConsumerState<AuraPage> {
  AuraCategory _tab = AuraCategory.frequency;

  void _openTrack(AuraTrack track) {
    // Alternating ad on track open (1st yes, 2nd no, ...). Diamonds awarded
    // automatically by AdService when an ad is actually shown.
    AdService.instance.showInterstitialAd(onAdDismissed: () async {
      await AuraPlayerService.instance.play(track);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AuraPlayerPage(track: track),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final freqs = ref.watch(auraFrequenciesProvider);
    final nature = ref.watch(auraNatureProvider);
    final list = _tab == AuraCategory.frequency ? freqs : nature;
    final isEs = LocaleHelper.isSpanishContext(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.spa, color: Color(0xFF7C4DFF), size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('AURA',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          isEs
                            ? 'Sonidos para sanar, descansar y dormir'
                            : 'Sounds to heal, rest and sleep',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Segmented control
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _Segmented(
                value: _tab,
                onChanged: (v) => setState(() => _tab = v),
                isEs: isEs,
              ),
            ),
            const SizedBox(height: 4),
            // Grid
            Expanded(
              child: list.when(
                data: (tracks) {
                  if (tracks.isEmpty) {
                    return const Center(
                      child: Text('No tracks yet', style: TextStyle(color: Colors.white54)),
                    );
                  }
                  return ListenableBuilder(
                    listenable: AuraPlayerService.instance,
                    builder: (_, __) {
                      final currentId = AuraPlayerService.instance.current?.id;
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: tracks.length,
                        itemBuilder: (_, i) {
                          final t = tracks[i];
                          return AuraTrackCard(
                            track: t,
                            isPlaying: t.id == currentId,
                            onTap: () => _openTrack(t),
                          );
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Error: $e', style: const TextStyle(color: Colors.redAccent)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  final AuraCategory value;
  final ValueChanged<AuraCategory> onChanged;
  final bool isEs;
  const _Segmented({required this.value, required this.onChanged, required this.isEs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          _seg(AuraCategory.frequency, isEs ? 'Frecuencias' : 'Frequencies'),
          _seg(AuraCategory.nature,    isEs ? 'Naturaleza'  : 'Nature'),
        ],
      ),
    );
  }

  Widget _seg(AuraCategory cat, String label) {
    final selected = value == cat;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(cat),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 38,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF7C4DFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : Colors.white.withOpacity(0.55),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/aura/presentation/pages/aura_page.dart
git commit -m "feat(aura): add AuraPage with segmented control and grid"
```

---

## Task 11: Sleep timer bottom sheet

**Files:**
- Create: `lib/features/aura/presentation/widgets/sleep_timer_sheet.dart`

- [ ] **Step 1: Write the sheet**

Create `lib/features/aura/presentation/widgets/sleep_timer_sheet.dart`:
```dart
import 'package:flutter/material.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../services/aura_player_service.dart';

class SleepTimerSheet extends StatelessWidget {
  const SleepTimerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const SleepTimerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEs = LocaleHelper.isSpanishContext(context);
    final options = const [5, 10, 15, 20, 30, 45, 60, 90];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.bedtime, color: Color(0xFF7C4DFF)),
                const SizedBox(width: 8),
                Text(
                  isEs ? 'Temporizador para dormir' : 'Sleep timer',
                  style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isEs ? 'La música se apagará suavemente' : 'Music will fade out softly',
              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: options.map((m) {
                return ElevatedButton(
                  onPressed: () {
                    AuraPlayerService.instance.startSleepTimer(Duration(minutes: m));
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A3E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  child: Text('$m min', style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                AuraPlayerService.instance.cancelSleepTimer();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.cancel_outlined, color: Colors.white54),
              label: Text(
                isEs ? 'Cancelar temporizador' : 'Cancel timer',
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/aura/presentation/widgets/sleep_timer_sheet.dart
git commit -m "feat(aura): add sleep timer bottom sheet"
```

---

## Task 12: AuraPlayerPage (full-screen player)

**Files:**
- Create: `lib/features/aura/presentation/pages/aura_player_page.dart`

- [ ] **Step 1: Write the page**

Create `lib/features/aura/presentation/pages/aura_player_page.dart`:
```dart
import 'package:flutter/material.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../data/models/aura_track.dart';
import '../../services/aura_player_service.dart';
import '../widgets/sleep_timer_sheet.dart';

class AuraPlayerPage extends StatefulWidget {
  final AuraTrack track;
  const AuraPlayerPage({super.key, required this.track});

  @override
  State<AuraPlayerPage> createState() => _AuraPlayerPageState();
}

class _AuraPlayerPageState extends State<AuraPlayerPage> {
  Color get _accent => widget.track.colorHex != null
      ? parseHexColor(widget.track.colorHex!, fallback: const Color(0xFF7C4DFF))
      : const Color(0xFF7C4DFF);

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _sleepLabel(BuildContext context) {
    final ends = AuraPlayerService.instance.sleepEndsAt;
    final isEs = LocaleHelper.isSpanishContext(context);
    if (ends == null) return isEs ? 'Temporizador' : 'Timer';
    final left = ends.difference(DateTime.now());
    if (left.isNegative) return isEs ? 'Temporizador' : 'Timer';
    return '${left.inMinutes + 1} min';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final isEs = LocaleHelper.isSpanishContext(context);
    final svc = AuraPlayerService.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.4,
            colors: [
              _accent.withOpacity(0.35),
              const Color(0xFF0A0A0F),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(
                      t.category == AuraCategory.frequency
                        ? (isEs ? 'FRECUENCIA' : 'FREQUENCY')
                        : (isEs ? 'NATURALEZA' : 'NATURE'),
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                        color: Colors.white.withOpacity(0.5),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              // Big icon / Hz
              Container(
                width: 200, height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [_accent.withOpacity(0.4), _accent.withOpacity(0.05)],
                  ),
                  boxShadow: [
                    BoxShadow(color: _accent.withOpacity(0.5), blurRadius: 60, spreadRadius: 4),
                  ],
                ),
                child: Center(
                  child: t.category == AuraCategory.frequency
                    ? Text('${t.hz} Hz',
                        style: const TextStyle(
                          fontSize: 38, fontWeight: FontWeight.bold, color: Colors.white))
                    : const Icon(Icons.spa, size: 80, color: Colors.white),
                ),
              ),
              const SizedBox(height: 30),
              // Title
              Text(t.displayName,
                style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              // Description card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Text(
                    t.displayDescription,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.75),
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const Spacer(),
              // Progress
              StreamBuilder<Duration>(
                stream: svc.positionStream,
                builder: (_, snap) {
                  final pos = snap.data ?? Duration.zero;
                  final dur = svc.duration ?? Duration(seconds: t.durationSec);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: _accent,
                            inactiveTrackColor: Colors.white.withOpacity(0.1),
                            thumbColor: _accent,
                            overlayColor: _accent.withOpacity(0.3),
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: pos.inSeconds.toDouble().clamp(0, dur.inSeconds.toDouble()),
                            max: dur.inSeconds.toDouble().clamp(1, double.infinity),
                            onChanged: (v) => svc.seek(Duration(seconds: v.toInt())),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(pos),
                              style: TextStyle(
                                fontSize: 11, color: Colors.white.withOpacity(0.5))),
                            Text(_fmt(dur),
                              style: TextStyle(
                                fontSize: 11, color: Colors.white.withOpacity(0.5))),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              // Controls
              ListenableBuilder(
                listenable: svc,
                builder: (_, __) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Loop
                      IconButton(
                        icon: Icon(
                          Icons.loop,
                          color: svc.loop ? _accent : Colors.white54,
                          size: 26,
                        ),
                        onPressed: () => svc.setLoop(!svc.loop),
                      ),
                      // Play/Pause
                      Container(
                        width: 70, height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _accent,
                          boxShadow: [
                            BoxShadow(color: _accent.withOpacity(0.6), blurRadius: 20, spreadRadius: 2),
                          ],
                        ),
                        child: IconButton(
                          icon: Icon(
                            svc.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white, size: 36,
                          ),
                          onPressed: () => svc.isPlaying ? svc.pause() : svc.resume(),
                        ),
                      ),
                      // Stop
                      IconButton(
                        icon: const Icon(Icons.stop, color: Colors.white54, size: 26),
                        onPressed: () async {
                          await svc.stop();
                          if (mounted) Navigator.pop(context);
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              // Sleep timer
              ListenableBuilder(
                listenable: svc,
                builder: (_, __) {
                  final active = svc.sleepEndsAt != null;
                  return TextButton.icon(
                    onPressed: () => SleepTimerSheet.show(context),
                    icon: Icon(
                      Icons.bedtime,
                      color: active ? _accent : Colors.white54,
                      size: 18,
                    ),
                    label: Text(
                      _sleepLabel(context),
                      style: TextStyle(color: active ? _accent : Colors.white54),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/aura/presentation/pages/aura_player_page.dart
git commit -m "feat(aura): add full-screen AuraPlayerPage with sleep timer"
```

---

## Task 13: Insert AURA tab into the bottom nav

**Files:**
- Modify: `lib/features/home/presentation/home_page.dart`

There are exactly **three** lists to keep in sync (`_pages`, `_title` titles, and `BottomNavigationBar.items`). Insert AURA after LIVE in all three.

- [ ] **Step 1: Add the import**

In `lib/features/home/presentation/home_page.dart`, near the other feature imports, add:
```dart
import '../../aura/presentation/pages/aura_page.dart';
```

- [ ] **Step 2: Insert into `_pages`**

Find the `_pages` list at line ~27 and add the AURA entry **immediately after** the `HotWallpapersPage` entry:
```dart
  static final _pages = [
    const WallpapersPage(),
    if (!Platform.isIOS) const HotWallpapersPage(),
    if (!Platform.isIOS) const AuraPage(),                // ← NEW
    if (!Platform.isIOS) const StoriesPage(),
    if (!Platform.isIOS) const DayCyclePage(),
    if (!Platform.isIOS) const RingtonesPage(),
    if (!Platform.isIOS) const AIGeneratePage(),
    const FavoritesPage(),
    const SettingsPage(),
  ];
```

- [ ] **Step 3: Insert into `_title`**

In the `titles` list inside `_title`, add the AURA title in the same position:
```dart
    final titles = [
      'Pixora IA',
      if (!Platform.isIOS) 'LIVE',
      if (!Platform.isIOS) 'AURA',                        // ← NEW
      if (!Platform.isIOS) 'Stories',
      if (!Platform.isIOS) 'Day Cycle',
      if (!Platform.isIOS) 'Tones',
      if (!Platform.isIOS) 'AI Create',
      'Favorites',
      'Settings',
    ];
```

- [ ] **Step 4: Insert into `BottomNavigationBar.items`**

After the LIVE item, add the AURA item with the lotus icon:
```dart
          if (!Platform.isIOS)
            const BottomNavigationBarItem(
              icon: Icon(Icons.spa),                       // lotus / spa icon
              label: 'AURA',
            ),
```

- [ ] **Step 5: Verify build & analyzer**

```bash
flutter analyze lib/features/home lib/features/aura
flutter build apk --debug
```

Expected: no analyzer errors, build succeeds.

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/presentation/home_page.dart
git commit -m "feat(aura): add AURA tab to bottom navigation after LIVE"
```

---

## Task 14: Track downloads + diamond reward

The user's requirement: "the same rules as wallpapers — alternating ads, every action grants diamond points." `AdService.showInterstitialAd` already does both (alternates and awards credits when an ad shows). We already call it on track open in Task 10. Now we add a second hook: a "Save offline" button on the player that always grants a small reward and shows an alternating ad.

**Files:**
- Modify: `lib/features/aura/services/aura_player_service.dart` (add download method using existing pattern)
- Create: `lib/features/aura/services/aura_download_service.dart`
- Modify: `lib/features/aura/presentation/pages/aura_player_page.dart` (add download button)

- [ ] **Step 1: Write the download service**

Create `lib/features/aura/services/aura_download_service.dart`:
```dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../data/models/aura_track.dart';

/// Saves AURA tracks to the app's documents dir for offline playback.
/// Mirrors the simple pattern used by RingtoneService.downloadTone.
class AuraDownloadService {
  AuraDownloadService._();
  static final instance = AuraDownloadService._();

  Future<File?> download(AuraTrack track) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final auraDir = Directory('${dir.path}/aura');
      if (!await auraDir.exists()) await auraDir.create(recursive: true);
      final file = File('${auraDir.path}/${track.id}.mp3');
      if (await file.exists()) return file;
      final r = await http.get(Uri.parse(track.audioUrl))
          .timeout(const Duration(seconds: 60));
      if (r.statusCode != 200) return null;
      await file.writeAsBytes(r.bodyBytes);
      return file;
    } catch (e) {
      debugPrint('[Pixora] AURA download failed: $e');
      return null;
    }
  }

  Future<bool> isDownloaded(AuraTrack track) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/aura/${track.id}.mp3').exists();
  }
}
```

- [ ] **Step 2: Add download button to player**

In `aura_player_page.dart`, import the download service and stats service at the top:
```dart
import '../../../../core/services/ad_service.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../services/aura_download_service.dart';
```

Inside the player's column, **just below the sleep timer button**, add:
```dart
              TextButton.icon(
                onPressed: () {
                  AdService.instance.showInterstitialAd(onAdDismissed: () async {
                    WallpaperStatsService.instance.trackDownload('aura_${t.id}');
                    final file = await AuraDownloadService.instance.download(t);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(file != null
                          ? (isEs ? 'Guardado para escuchar sin internet' : 'Saved for offline')
                          : (isEs ? 'No se pudo descargar' : 'Download failed')),
                        backgroundColor: file != null ? Colors.green : Colors.red,
                      ),
                    );
                  });
                },
                icon: const Icon(Icons.download, size: 18, color: Colors.white54),
                label: Text(
                  isEs ? 'Guardar offline' : 'Save offline',
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
```

- [ ] **Step 3: Verify**

```bash
flutter analyze lib/features/aura
```

Expected: no errors. (`http` and `path_provider` are already in `pubspec.yaml` — they're used by other services. If `flutter analyze` complains about missing imports, run `flutter pub get`.)

- [ ] **Step 4: Commit**

```bash
git add lib/features/aura/services/aura_download_service.dart lib/features/aura/presentation/pages/aura_player_page.dart
git commit -m "feat(aura): add offline download with alternating ad + diamond reward"
```

---

## Task 15: End-to-end smoke test on device

- [ ] **Step 1: Build & install debug APK**

```bash
flutter run
```

(Or `./gradlew installDebug` and launch manually.)

- [ ] **Step 2: Functional checklist**

Tap through and verify each item:

- [ ] AURA tab appears in the bottom nav with the lotus icon, label "AURA"
- [ ] Tapping AURA opens the page; **Frequencies** segment shows 9 cards with Hz labels
- [ ] **Nature** segment shows 15 cards with category icons
- [ ] Tapping a card opens the full-screen player after the (alternating) ad flow
- [ ] Player shows track title, bilingual description (switches if device locale is es-*), Hz badge / spa icon
- [ ] Play/pause works
- [ ] Loop toggle changes color when active
- [ ] Stop button stops playback and pops the player
- [ ] Slider seeks correctly
- [ ] Sleep timer sheet opens, choosing 5 min schedules a fade-out at the right time
- [ ] **Close the app entirely** (swipe from recents) — playback continues with a notification you can tap to pause
- [ ] Re-open the app — current track and player state are preserved
- [ ] "Save offline" button downloads the file (verify with `adb shell run-as com.orbix.pixora ls /data/user/0/com.orbix.pixora/files/aura`)
- [ ] Diamond counter in the top bar increases after watching an ad (and alternates: 1st action shows ad, 2nd doesn't)

- [ ] **Step 3: Tag milestone**

```bash
git tag aura-app-v1
```

---

## Done criteria

- AURA tab present and functional on a real Android device
- Both segments render real tracks fetched from `public.aura_tracks`
- Background playback survives app close and shows a media notification
- Sleep timer fades out and stops at the chosen time
- Bilingual descriptions render correctly on both `en_US` and `es_MX` locales
- Alternating ads and diamond rewards behave the same as wallpapers
- All flutter analyze checks pass; debug APK builds clean
