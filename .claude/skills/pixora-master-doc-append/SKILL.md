---
name: pixora-master-doc-append
description: "Use to safely append content to the Pixora master document (Google Drive .docx) without rewriting existing sections. Handles the python-docx boilerplate, enforces the append-only rule, redacts secrets, takes a snapshot before writing, and commits the docx update. Trigger on 'actualiza el doc maestro', 'agrega al documento maestro', 'update master doc', or any time a section needs new content added (release notes, version bumps, feature status, credential inventory, learned pitfalls)."
---

# Pixora Master Doc Append

The master document at `G:/Mi unidad/pixoraIA_admin/admin/administracion/Pixora_IA_Documento_Maestro.docx` is the canonical source of truth for Pixora's business, product, and secrets inventory. This skill wraps the correct way to update it so we never lose content or leak secrets.

## Golden rules

1. **Append, never rewrite** — existing paragraphs stay intact, even if they contain typos or outdated info. Mention the need for a rewrite to the user; don't silently fix.
2. **Snapshot before write** — copy the current `.docx` to `docs/master_doc_snapshots/YYYY-MM-DD_<sha8>.docx` (gitignored dir) so we can diff/rollback.
3. **Redact secrets** — never paste actual key values into sections that might get mirrored to public places. Reference `KEYS_LOCAL.md` by name.
4. **Respect section numbering** — find the right sub-section number before appending. Append as the next sub-section (e.g. if §14.13 is the last, add §14.14).

## Section map (where things belong)

| Content | Section |
|---|---|
| New feature shipped | §7 (Arquitectura) + new status sub-section |
| Business/monetization decision | §8 (Modelo de Negocio) |
| New version bump, release notes | §12 (Registro de Versiones) |
| New credential, rotation | §11 (Seguridad) — reference KEYS_LOCAL, never paste value |
| Platform pitfall learned | "Lecciones aprendidas" sub-section |
| AURA frequency added | §14.3 |
| AURA nature track added | §14.4 |
| AURA module status update | §14.10+ (find next available number) |
| Test/verification reports | §14.13+ |

If the content doesn't fit any section, ask the user where it should go rather than creating a new top-level section.

## The append pattern

```python
from docx import Document
from pathlib import Path
import hashlib, shutil
from datetime import date

SRC = Path(r"G:/Mi unidad/pixoraIA_admin/admin/administracion/Pixora_IA_Documento_Maestro.docx")
SNAP_DIR = Path(r"D:/Orbix/Pixora-IA/docs/master_doc_snapshots")

# 1. Snapshot
SNAP_DIR.mkdir(parents=True, exist_ok=True)
sha8 = hashlib.sha256(SRC.read_bytes()).hexdigest()[:8]
snap = SNAP_DIR / f"{date.today().isoformat()}_{sha8}.docx"
if not snap.exists():
    shutil.copy2(SRC, snap)
    print(f"Snapshot: {snap.name}")

# 2. Append
doc = Document(str(SRC))
doc.add_heading("X.Y New sub-section title", level=2)

def kv(label, value):
    p = doc.add_paragraph()
    p.add_run(label + ": ").bold = True
    p.add_run(value)

def bullet(text):
    doc.add_paragraph(text, style='List Bullet')

# Your content here — use kv() for key-value, bullet() for lists, plain
# doc.add_paragraph() for narrative.

doc.save(str(SRC))
print("OK — master doc updated")
```

## Redaction checklist (run before writing)

If the content mentions any of these, STOP and redact to a reference instead:

- JWTs matching `eyJhbGc...` → replace with `(see KEYS_LOCAL.md — Supabase section)`
- Google OAuth client IDs (`*.apps.googleusercontent.com`) → replace with `(see KEYS_LOCAL.md — OAuth section)`
- `GOCSPX-...` secrets → replace
- `ghp_...`, `github_pat_...` GitHub tokens → replace
- Keystore passwords → replace
- Freesound API keys → replace
- Service account JSON blobs → replace

The exception: if the section being written is itself "inventory of where secrets live", you can paste the placeholder labels but never the actual values.

## After writing

1. Print the first 3 lines of what you appended so the user can sanity-check.
2. Commit the snapshot if it's new: `git add .gitignore` (only if you had to update gitignore) — note the snapshot file itself is gitignored, this is just in case.
3. If the update was part of a larger flow (release, feature ship), return control to the calling skill.

## Reporting

```
📄 Master Doc Append
  Snapshot:  ✅ docs/master_doc_snapshots/<filename>.docx (or: unchanged)
  Section:   §X.Y <title>
  Content:   <N> paragraphs, <M> bullets, <K> key-values
  Redacted:  <list of secret types replaced, or "none">
  Status:    ✅ saved
```

## What NOT to do

- Don't rewrite existing paragraphs, even to fix typos — ask first.
- Don't paste secret values. Ever. Reference KEYS_LOCAL.
- Don't create a new top-level section without user confirmation.
- Don't commit the .docx itself to git (it's not in the repo anyway — it lives in Drive).
- Don't skip the snapshot. It's the only rollback mechanism we have for Drive.
