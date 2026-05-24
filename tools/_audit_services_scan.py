"""Scan all services for known antipatterns we found in deep audit."""
import os, re, sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

LIB = r"D:/Orbix/Pixora-IA/lib"

# Patterns
PATTERNS = {
    'null_assertion_after_login_guard': re.compile(
        r'(?:_isLoggedIn|isLoggedIn|currentUser\s*!=\s*null)[^}]*?(?:currentUser!|currentUser\?\.id\s*!|_userId!)',
        re.DOTALL
    ),
    'init_marks_true_before_end': re.compile(
        r'_initialized\s*=\s*true.*?await', re.DOTALL
    ),
    'orphan_listen': re.compile(
        r'(?<!=\s)\.listen\s*\('
    ),
    'force_unwrap_after_await': re.compile(
        r'await[^;]+;\s*[^}]*?(\w+)!\.'
    ),
}

services = []
for root, _, files in os.walk(LIB):
    for fn in files:
        if not fn.endswith('.dart'): continue
        path = os.path.join(root, fn)
        rel = os.path.relpath(path, r"D:/Orbix/Pixora-IA").replace(os.sep, '/')
        try:
            content = open(path, encoding='utf-8').read()
        except: continue
        # Only services
        if 'static final instance' not in content: continue
        if '/services/' not in rel and '/data/' not in rel: continue

        hits = {}
        for name, pat in PATTERNS.items():
            matches = list(pat.finditer(content))
            if matches:
                hits[name] = len(matches)
        if hits:
            services.append((rel, hits))

print("=== Pattern hits per service ===")
for rel, hits in sorted(services):
    print(f"\n{rel}:")
    for pattern, count in hits.items():
        print(f"  {pattern}: {count}")
