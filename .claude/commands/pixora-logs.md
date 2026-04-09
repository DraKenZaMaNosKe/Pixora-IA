---
description: "Filter Samsung logcat by a pattern — quick debug shortcut. Usage: /pixora-logs <pattern>"
---

Read logcat from the Samsung device (`RF8X903KZ3K`) and filter it. The pattern to search for is: **{{args}}**

If `{{args}}` is empty or not meaningful, default to `flutter|Pixora|FATAL|AndroidRuntime` — the generic "something relevant to Pixora" filter.

Run:
```bash
adb -s RF8X903KZ3K logcat -d 2>&1 | grep -iE "{{args}}" | tail -60
```

Then:

1. If there are matches, show the last 30-60 lines, trimmed to be readable (strip tags if noisy).
2. If there are ZERO matches, say clearly: "No matches for `{{args}}` in the last logcat buffer."
3. If you see any FATAL, AndroidRuntime crash, or Flutter Uncaught error, highlight them at the top with ⚠️ before showing the rest.

Keep the output compact — this is a quick peek, not a deep dive. If the user wants more, they'll ask.
