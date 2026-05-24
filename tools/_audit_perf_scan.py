"""Performance audit scan for Pixora."""
import os, re, sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

LIB = r"D:/Orbix/Pixora-IA/lib"

findings = {
    'image_cache_config': [],      # Where imageCache config is touched
    'large_lists_no_builder': [],   # Column/Row with many children (suggests ListView.builder)
    'sync_io_main_isolate': [],    # File.readAsString sync etc.
    'image_provider_no_dispose': [], # ImageProvider that may leak
    'rebuilt_constants': [],        # Containers/Text in build without const
    'jsonDecode_large': [],         # jsonDecode in build/onTap (may block)
    'setState_in_loop': [],         # setState inside for loop (rebuild storm)
    'http_no_timeout': [],          # http.get/post without timeout
    'cached_network_image_unconfigured': [], # CachedNetworkImage without cacheWidth
}

for root, _, files in os.walk(LIB):
    for fn in files:
        if not fn.endswith('.dart'): continue
        path = os.path.join(root, fn)
        rel = os.path.relpath(path, r"D:/Orbix/Pixora-IA").replace(os.sep, '/')
        try:
            content = open(path, encoding='utf-8').read()
        except: continue
        lines = content.split('\n')

        # 1. imageCache config
        if re.search(r'PaintingBinding\.instance\.imageCache|imageCache\.maximum', content):
            findings['image_cache_config'].append(rel)

        # 2. sync IO main isolate
        for m in re.finditer(r'\.readAsStringSync\(|\.readAsBytesSync\(', content):
            ln = content[:m.start()].count('\n') + 1
            findings['sync_io_main_isolate'].append(f"{rel}:{ln}")

        # 3. jsonDecode of large in build
        for m in re.finditer(r'jsonDecode\(', content):
            ln = content[:m.start()].count('\n') + 1
            ctx = '\n'.join(lines[max(0,ln-3):min(len(lines),ln+1)])
            if 'build(' in ctx or 'onTap' in ctx:
                findings['jsonDecode_large'].append(f"{rel}:{ln}")

        # 4. http without timeout
        for m in re.finditer(r'http\.(get|post|put|delete)\(', content):
            ln = content[:m.start()].count('\n') + 1
            ctx = '\n'.join(lines[ln-1:min(len(lines),ln+3)])
            if 'timeout' not in ctx.lower() and '.timeout(' not in ctx:
                findings['http_no_timeout'].append(f"{rel}:{ln}")

        # 5. setState in for loop
        for m in re.finditer(r'for\s*\(.+?\)\s*\{[^}]*setState\(', content, re.DOTALL):
            ln = content[:m.start()].count('\n') + 1
            findings['setState_in_loop'].append(f"{rel}:{ln}")

        # 6. CachedNetworkImage sin cacheWidth/Height (memory-bound)
        for m in re.finditer(r'CachedNetworkImage\(', content):
            ln = content[:m.start()].count('\n') + 1
            # Look in next 10 lines for cacheWidth or memCacheWidth
            ctx = '\n'.join(lines[ln-1:min(len(lines),ln+15)])
            if 'memCacheWidth' not in ctx and 'memCacheHeight' not in ctx:
                findings['cached_network_image_unconfigured'].append(f"{rel}:{ln}")

print("=== Performance scan results ===\n")
for name, hits in findings.items():
    if not hits:
        print(f"  {name}: 0 ✓")
        continue
    print(f"\n{name}: {len(hits)}")
    for h in hits[:10]:
        print(f"  - {h}")
    if len(hits) > 10:
        print(f"  ... +{len(hits)-10} more")
