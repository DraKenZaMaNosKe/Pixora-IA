"""One-shot: scan Pixora lib/ for common antipatterns."""
import os, re
import sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

LIB = r"D:/Orbix/Pixora-IA/lib"
controllers_re = re.compile(r'\b(AnimationController|VideoPlayerController|AudioPlayer|StreamSubscription|TextEditingController|ScrollController|PageController|FocusNode|TabController)\b')

leaks = []
setstate_no_mounted = []

setstate_after_await = re.compile(r'await[^;]*;[\s\n]*(?://[^\n]*\n[\s]*)*setState\(', re.MULTILINE)

for root, _, files in os.walk(LIB):
    for fn in files:
        if not fn.endswith('.dart'):
            continue
        path = os.path.join(root, fn)
        rel = os.path.relpath(path, r"D:/Orbix/Pixora-IA")
        rel = rel.replace(os.sep, '/')
        try:
            content = open(path, encoding='utf-8').read()
        except Exception:
            continue

        # 1. StatefulWidget with controllers but no dispose
        if 'extends State<' in content and controllers_re.search(content):
            if 'void dispose()' not in content:
                ctrls = set(controllers_re.findall(content))
                leaks.append((rel, ctrls))

        # 2. setState after await without mounted check nearby
        lines = content.split('\n')
        for m in setstate_after_await.finditer(content):
            ln = content[:m.start()].count('\n') + 1
            ctx = '\n'.join(lines[max(0, ln - 4):min(len(lines), ln + 2)])
            if 'mounted' not in ctx:
                setstate_no_mounted.append((rel, ln))

print("=== StatefulWidget sin dispose() (potential leak):", len(leaks), "===")
for path, ctrls in leaks[:20]:
    print("  X", path)
    print("     uses:", ", ".join(sorted(ctrls)))

print()
print("=== setState despues de await SIN mounted check:", len(setstate_no_mounted), "===")
for path, ln in setstate_no_mounted[:30]:
    print("  !", f"{path}:{ln}")
