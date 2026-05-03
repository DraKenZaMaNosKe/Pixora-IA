---
name: pixora-release-prep
description: "Use to prepare a Play Store release of Pixora — bumps version if needed, verifies clean working tree, runs full analyze + release AAB build + signature verification, generates bilingual (ES/EN) release notes from commits since the last tag, updates master doc §12, creates the git tag, and prompts before pushing. Trigger on 'preparar release', 'subir versión', 'nueva versión', 'release a Play Store', or when the user bumps version in pubspec.yaml."
---

# Pixora Release Preparation

Turns the error-prone "get a build to Play Store" flow into a single skill with gates. Every step has a stop condition so nothing ships half-done.

## Preconditions (check first, stop if any fail)

1. **Working tree clean**: `git status -s` returns empty. If not, stop and ask the user to commit/stash.
2. **On `play-store-estable` or a release branch**: `git rev-parse --abbrev-ref HEAD`. Warn if on `main` or a feature branch.
3. **Master doc reachable**: `G:/Mi unidad/pixoraIA_admin/admin/administracion/Pixora_IA_Documento_Maestro.docx` exists.
4. **KEYS_LOCAL.md present**: needed to read the keystore password (don't read the actual password — just confirm the file exists for the script).

## The flow

### Phase 1 — Version

Read current version from `pubspec.yaml`:
```bash
grep "^version:" pubspec.yaml
```
Format: `X.Y.Z+N`. Ask the user if this is the version they want to ship, or if we bump first.

If bumping: edit `pubspec.yaml`, commit as `chore: bump version to X.Y.Z+N`.

### Phase 2 — Analyzer on full codebase
```bash
flutter analyze lib/
```
**Must be 0 errors**. Info/warnings are OK but note count in the report.

### Phase 3 — Release AAB build
```bash
flutter build appbundle --release
```
Expected: `build/app/outputs/bundle/release/app-release.aab`.
**Stop if**: build fails. Report last 30 lines.

### Phase 4 — Verify signing
```bash
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab | tail -20
```
Look for `jar verified` and the expected SHA-1 (`FF:0F:46:D4:E2:86:25:D1:14:C6:81:03:11:E4:6B:E4:47:2A:CD:79` — the current upload key as of v1.7.0). If SHA doesn't match, stop — wrong keystore.

### Phase 5 — Collect commits since last tag
```bash
LAST_TAG=$(git describe --tags --abbrev=0)
git log ${LAST_TAG}..HEAD --oneline --no-merges
```
Group them by Conventional-Commit type:
- `feat(...)` → "Added / Agregado"
- `fix(...)` → "Fixed / Corregido"
- `perf(...)` → "Improved / Mejorado"
- `refactor(...)`, `chore(...)` → skip from user-facing notes

### Phase 6 — Draft bilingual release notes

Draft in two blocks, each **under 500 characters** (Play Store hard limit):

```
## English (<500 chars)
- <feature>
- <fix>
...

## Español (<500 chars)
- <feature traducida>
- <fix traducido>
...
```

**Show to user and wait for approval** before writing anywhere. User can edit. Iterate if needed.

### Phase 7 — Save release notes

Once approved, save to `docs/release_notes/vX.Y.Z.md` with both blocks + the commit SHA list at the bottom for traceability. Commit as `docs(release): notes for vX.Y.Z`.

### Phase 8 — Update master doc §12

Append a sub-section to §12 "Registro de Versiones":
```
vX.Y.Z+N — YYYY-MM-DD
  • <bullet EN>
  • <bullet ES>
  • Commit: <SHA>
  • AAB SHA-1: FF:0F:46:...
```

Use `python-docx` with the `pixora-master-doc-append` skill's append pattern.

### Phase 9 — Tag
```bash
git tag vX.Y.Z
```
(Annotated tag is overkill for Pixora's solo workflow; lightweight is fine.)

### Phase 10 — Push gate

**STOP and ask the user**: "Release prepared. Push tag and commits to origin? [y/N]"

Only on explicit `y`:
```bash
git push origin play-store-estable
git push origin vX.Y.Z
```

Never force-push. Never push `--tags` blindly.

## Reporting

```
🚀 Release Prep — vX.Y.Z+N
  Working tree:    ✅ clean
  Analyzer:        ✅ 0 errors
  AAB build:       ✅ build/app/outputs/bundle/release/app-release.aab (N MB)
  Signing:         ✅ SHA-1 matches Play Store key
  Commits since:   <last_tag> → N commits grouped
  Release notes:   ✅ approved + saved
  Master doc §12:  ✅ appended
  Git tag:         ✅ vX.Y.Z created (local)
  Push:            ⏸️  awaiting user confirmation
```

After the user says push:
```
  Push:            ✅ origin updated
```

## What NOT to do

- Don't push without explicit user confirmation.
- Don't skip the signing verification — a wrongly-signed AAB is rejected by Play Store and wastes a day.
- Don't auto-write release notes without showing them to the user first.
- Don't bump version silently.
- Don't tag before the AAB verifies.
