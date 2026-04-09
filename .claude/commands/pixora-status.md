---
description: "Show a compact Pixora status dashboard — where am I, what's in flight, is the catalog healthy"
---

Run a compact Pixora status check and show me a dashboard I can scan in 5 seconds:

1. **Git state** — current branch, uncommitted file count, last 3 commits (use `git rev-parse --abbrev-ref HEAD`, `git status -s | wc -l`, `git log --oneline -3`)
2. **Version** — from `pubspec.yaml` (grep `^version:`)
3. **Supabase AURA catalog** — use the Supabase MCP `execute_sql` tool against project `vzuwvsmlyigjtsearxym` to run `select category, count(*) from public.aura_tracks group by category`. Expected: `frequency=9`, `nature=15`.
4. **Last debug build artifact** — check if `build/app/outputs/flutter-apk/app-debug.apk` exists and its age via `ls -l` or `stat`. Report as "built N minutes/hours ago" or "not built".
5. **Connected devices** — `adb devices` output, highlight `RF8X903KZ3K` (Samsung) if present.

Format as a compact block:

```
🎯 Pixora Status
  Branch:    <branch>
  Version:   <version>
  Changes:   <N> uncommitted files
  Commits:   <last 3, one line each>
  AURA DB:   frequency=9 ✅  nature=15 ✅  (or ❌ with counts)
  APK:       <age or "not built">
  Devices:   <list, ✅ if Samsung present>
```

Don't do any other work — just the status. If anything is red (e.g. missing tracks, Samsung disconnected, etc.), mention it with ⚠️ and briefly suggest what to check, but don't auto-fix.
