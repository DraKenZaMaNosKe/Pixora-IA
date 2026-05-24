"""Scan native Kotlin for common Android antipatterns."""
import os, re, sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ANDROID = r"D:/Orbix/Pixora-IA/android/app/src/main/kotlin"

PATTERNS = {
    'handler_postDelayed_no_remove': re.compile(r'postDelayed\s*\('),
    'register_receiver_no_unregister': re.compile(r'registerReceiver\s*\('),
    'choreographer_no_remove': re.compile(r'postFrameCallback\s*\('),
    'mediaplayer_create': re.compile(r'MediaPlayer\s*\('),
    'bitmap_no_recycle': re.compile(r'BitmapFactory\.decode'),
    'surface_no_release': re.compile(r'Surface\s*\('),
    'thread_start': re.compile(r'Thread\s*\(.*?\)\s*\.start|Executors\.newSingleThreadExecutor'),
    'context_static': re.compile(r'companion\s+object[^}]+\w+:\s*Context\s*\?', re.DOTALL),
    'gc_call': re.compile(r'System\.gc\(\)|Runtime\.getRuntime\(\)\.gc\(\)'),
    'sleep_main_thread': re.compile(r'Thread\.sleep\('),
    'large_object_member': re.compile(r'(?:private\s+|val\s+|var\s+).*Activity\s*[?=]'),
}

REMOVE_PATTERNS = {
    'handler_postDelayed_no_remove': re.compile(r'removeCallbacks|removeCallbacksAndMessages'),
    'register_receiver_no_unregister': re.compile(r'unregisterReceiver'),
    'choreographer_no_remove': re.compile(r'removeFrameCallback'),
    'bitmap_no_recycle': re.compile(r'\.recycle\(\)'),
}

findings = {}

for root, _, files in os.walk(ANDROID):
    for fn in files:
        if not fn.endswith('.kt'): continue
        path = os.path.join(root, fn)
        rel = os.path.relpath(path, ANDROID).replace(os.sep, '/')
        try:
            content = open(path, encoding='utf-8').read()
        except: continue

        for pname, pat in PATTERNS.items():
            matches = list(pat.finditer(content))
            if matches:
                # If has corresponding remove pattern, OK
                if pname in REMOVE_PATTERNS:
                    if REMOVE_PATTERNS[pname].search(content):
                        continue
                findings.setdefault(pname, []).append((rel, len(matches)))

print("=== Kotlin antipattern scan ===")
print()
for pname, hits in sorted(findings.items()):
    print(f"{pname}: {len(hits)} files")
    for rel, count in hits[:8]:
        print(f"  - {rel} ({count}x)")
    if len(hits) > 8:
        print(f"  ... +{len(hits)-8} more")
    print()
