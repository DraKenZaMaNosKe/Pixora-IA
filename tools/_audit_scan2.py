"""Audit scan #2: streams sin cancel + try sin catch + Future.delayed sin re-mounted-check"""
import os, re
import sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

LIB = r"D:/Orbix/Pixora-IA/lib"

# Patrón específico: if (mounted) { ... await Future.delayed ... setState OTRA VEZ }
# El segundo setState NO re-checkea mounted.
delayed_setstate = re.compile(
    r'await\s+Future\.delayed\([^)]+\)\s*;[\s\n]*(?://[^\n]*\n[\s]*)*setState\(',
    re.MULTILINE
)

# StreamSubscription declarada pero no .cancel() en dispose
stream_subs = re.compile(r'StreamSubscription[^;]*\?\s+(\w+)')
cancel_pattern = re.compile(r'(\w+)\?\.cancel\(\)|(\w+)\.cancel\(\)')

# .listen( sin asignar a variable (orphan listener — nunca puede cancelarse)
orphan_listen = re.compile(r'(?<!=\s)\.listen\s*\(')

delayed_bugs = []
orphan_listens = []
unhandled_subs = []

for root, _, files in os.walk(LIB):
    for fn in files:
        if not fn.endswith('.dart'):
            continue
        path = os.path.join(root, fn)
        rel = os.path.relpath(path, r"D:/Orbix/Pixora-IA").replace(os.sep, '/')
        try:
            content = open(path, encoding='utf-8').read()
        except Exception:
            continue
        lines = content.split('\n')

        # 1. await Future.delayed → setState sin re-check mounted
        for m in delayed_setstate.finditer(content):
            ln = content[:m.start()].count('\n') + 1
            # Check 3 lines AFTER the await for 'mounted' or 'if (!mounted) return'
            ctx_after = '\n'.join(lines[ln-1:min(len(lines), ln+3)])
            # If no mounted check between Future.delayed and the next setState, BUG
            # The match itself spans Future.delayed → setState, so if mounted is
            # in the matched text, false positive. Check the actual match text.
            match_text = m.group(0)
            if 'mounted' not in match_text:
                delayed_bugs.append((rel, ln))

        # 2. .listen( sin asignar (orphan)
        for m in orphan_listen.finditer(content):
            ln = content[:m.start()].count('\n') + 1
            # Look 1 line back to confirm it's not assigned
            prev = lines[max(0, ln-2):ln]
            joined = ' '.join(prev)
            if '=' not in joined.split('.listen')[0][-50:]:
                orphan_listens.append((rel, ln, lines[ln-1].strip()[:80]))

        # 3. StreamSubscriptions declaradas sin cancel en el archivo
        subs_declared = set(stream_subs.findall(content))
        if subs_declared:
            # Encuentra todas las cancel() llamadas
            cancels = set()
            for m in cancel_pattern.finditer(content):
                cancels.add(m.group(1) or m.group(2))
            missing = subs_declared - cancels
            if missing:
                unhandled_subs.append((rel, sorted(missing)))


print("=== Future.delayed -> setState sin re-mounted check:", len(delayed_bugs), "===")
for path, ln in delayed_bugs[:20]:
    print(f"  ! {path}:{ln}")

print()
print("=== StreamSubscription declarada SIN .cancel():", len(unhandled_subs), "===")
for path, missing in unhandled_subs[:15]:
    print(f"  ! {path}  vars: {', '.join(missing)}")

print()
print("=== .listen() sin asignar (orphan, no cancellable):", len(orphan_listens), "===")
for path, ln, ctx in orphan_listens[:15]:
    print(f"  ! {path}:{ln}")
    print(f"      {ctx}")
