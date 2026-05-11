"""Sanitize secrets from master doc HTML before public deploy."""
import re
from pathlib import Path

SRC = Path(r"D:/Orbix/Pixora-IA/docs/master_doc/index.html")
DST = Path(r"C:/Users/lalo/AppData/Local/Temp/intrapcsolutions-web/privado/master/index.html")

content = SRC.read_text(encoding="utf-8")
original_len = len(content)

REDACTED = "(REDACTADO - ver KEYS_LOCAL.md)"

patterns = [
    # Google OAuth Client IDs
    (r"\d{12}-[a-z0-9]+\.apps\.googleusercontent\.com", REDACTED),
    # Google OAuth Client Secrets
    (r"GOCSPX-[A-Za-z0-9_-]+", REDACTED),
    # AdMob unit IDs (real ones, not test)
    (r"ca-app-pub-\d{16}/\d{10}", REDACTED),
    (r"ca-app-pub-\d{16}~\d{10}", REDACTED),
    # Supabase JWTs (anon key + service role key)
    (r"eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", REDACTED),
    # GitHub Personal Access Tokens
    (r"ghp_[A-Za-z0-9]{36,}", REDACTED),
    (r"github_pat_[A-Za-z0-9_]{82,}", REDACTED),
    # Generic API keys (32-64 hex chars in context of API)
    # Freesound API keys (32 hex chars)
    (r"\b[a-f0-9]{32}\b", REDACTED),
    # SHA1 fingerprints (20 bytes hex with colons)
    # Keep these visible since they're meant to be public (cert fingerprints)
]

count = 0
for pattern, replacement in patterns:
    new_content, n = re.subn(pattern, replacement, content)
    if n > 0:
        print(f"[SAN] {pattern[:50]}... -> {n} replacements")
        count += n
    content = new_content

# Add a banner at top noting sanitization
banner = """<div style="background:#FFE8E8;border-left:4px solid #FF3B30;padding:12px 16px;margin:0;font-family:monospace;font-size:12px;color:#6B1414;">
<b>NOTA:</b> Esta version del documento maestro tiene secretos REDACTADOS para deploy publico. Para valores reales consulta KEYS_LOCAL.md o Documento Maestro original (.docx).
</div>
"""
# Insert banner after <body>
content = content.replace("<body>", "<body>\n" + banner, 1)

DST.parent.mkdir(parents=True, exist_ok=True)
DST.write_text(content, encoding="utf-8")

new_len = len(content)
print(f"\nOriginal: {original_len} bytes")
print(f"Sanitized: {new_len} bytes")
print(f"Total replacements: {count}")
print(f"Saved to: {DST}")
