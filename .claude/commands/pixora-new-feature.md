---
description: "Scaffold a new Flutter feature folder with Pixora's standard layout. Usage: /pixora-new-feature <name>"
---

Scaffold a new feature module under `lib/features/{{args}}/` following the Pixora standard layout.

### Validate first

- If `{{args}}` is empty, stop and ask the user for a feature name.
- The name should be snake_case. If it has spaces or uppercase, normalize it or ask.
- If `lib/features/{{args}}/` already exists, stop and warn — don't overwrite.

### Directory structure to create

```
lib/features/{{args}}/
├── data/
│   ├── models/
│   │   └── {{args}}_item.dart
│   └── repositories/
├── presentation/
│   ├── pages/
│   │   └── {{args}}_page.dart
│   └── widgets/
├── providers/
│   └── {{args}}_providers.dart
└── services/      (empty for now; only add files here if the feature owns a singleton)
```

### File templates to write

**`lib/features/{{args}}/data/models/{{args}}_item.dart`** — stub model:
```dart
class {{args_pascal}}Item {
  final String id;

  const {{args_pascal}}Item({required this.id});

  factory {{args_pascal}}Item.fromJson(Map<String, dynamic> json) {
    return {{args_pascal}}Item(
      id: json['id'] as String,
    );
  }
}
```

(Replace `{{args_pascal}}` with PascalCase version of `{{args}}` — e.g. `user_profile` → `UserProfile`.)

**`lib/features/{{args}}/providers/{{args}}_providers.dart`** — empty providers file:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Providers for {{args}} feature — add as needed.
```

**`lib/features/{{args}}/presentation/pages/{{args}}_page.dart`** — minimal placeholder page:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class {{args_pascal}}Page extends ConsumerStatefulWidget {
  const {{args_pascal}}Page({super.key});

  @override
  ConsumerState<{{args_pascal}}Page> createState() => _{{args_pascal}}PageState();
}

class _{{args_pascal}}PageState extends ConsumerState<{{args_pascal}}Page> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A0A0F),
      body: Center(
        child: Text(
          '{{args}} — coming soon',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      ),
    );
  }
}
```

### After scaffolding

1. **Do NOT modify `home_page.dart` yet.** Ask the user: "¿Quieres que agregue este feature como tab en el bottom nav? ¿En qué posición?"
2. Print a compact report:
   ```
   ✨ Scaffolded lib/features/{{args}}/
     ├── data/models/{{args}}_item.dart     (stub model)
     ├── presentation/pages/{{args}}_page.dart  (placeholder)
     └── providers/{{args}}_providers.dart    (empty)

   Next: bottom nav integration? (ask user)
   ```
3. Run `flutter analyze lib/features/{{args}}/` to confirm no errors.
4. Do NOT commit automatically — that's a separate conscious step.
