"""
Render the Pixora Master Document (.docx) as a Brutalist Tech HTML
single-page web document. Preserves heading hierarchy, body text,
and produces a navigable left sidebar with ALL sections.

Output: D:/Orbix/Pixora-IA/docs/master_doc/index.html
        (+ a static CSS file we ship alongside)

Run:    python tools/docs/render_master_doc_brutalist.py
"""
from __future__ import annotations
import re
import sys
from pathlib import Path
from datetime import datetime

sys.stdout.reconfigure(encoding="utf-8")

from docx import Document

SRC = Path(r"G:/Mi unidad/pixoraIA_admin/admin/administracion/Pixora_IA_Documento_Maestro.docx")
OUT_DIR = Path(r"D:/Orbix/Pixora-IA/docs/master_doc")
OUT_DIR.mkdir(parents=True, exist_ok=True)


def slugify(s: str) -> str:
    s = re.sub(r"[^\w\s-]", "", s.lower())
    s = re.sub(r"[\s_-]+", "-", s).strip("-")
    return s[:80] or "section"


def escape(s: str) -> str:
    return (s.replace("&", "&amp;")
             .replace("<", "&lt;")
             .replace(">", "&gt;"))


def render():
    doc = Document(str(SRC))
    body_html = []
    nav_html = []
    used_ids = set()

    def unique_id(base: str) -> str:
        i = 1
        sid = base
        while sid in used_ids:
            i += 1
            sid = f"{base}-{i}"
        used_ids.add(sid)
        return sid

    for p in doc.paragraphs:
        text = p.text.strip()
        if not text:
            continue
        style = p.style.name
        # Heading level
        level = None
        if style == "Title":
            level = 1
        elif style.startswith("Heading"):
            try:
                level = int(style.replace("Heading ", ""))
            except ValueError:
                level = 2

        if level is not None:
            sid = unique_id(slugify(text))
            tag = f"h{min(level, 4)}"
            label_class = f"hd-l{min(level, 4)}"
            body_html.append(
                f'<{tag} id="{sid}" class="{label_class}">'
                f'<span class="hd-marker">{"#" * level}</span> '
                f'{escape(text)}</{tag}>'
            )
            nav_html.append(
                f'<a href="#{sid}" class="nav-l{min(level,4)}">'
                f'<span class="nav-bar">{"&middot;"*level}</span>'
                f'{escape(text[:60])}{"…" if len(text) > 60 else ""}</a>'
            )
        elif style == "List Bullet":
            body_html.append(f'<li>{escape(text)}</li>')
        elif style == "Quote":
            body_html.append(
                f'<pre class="quote">{escape(text)}</pre>'
            )
        else:
            # Detect bold-prefix patterns like "Label: value" we use a lot
            m = re.match(r"^([A-ZÁÉÍÓÚÑ][^:]{1,40}):\s*(.+)$", text)
            if m and len(m.group(1)) <= 30:
                body_html.append(
                    f'<p class="kv"><b>{escape(m.group(1))}:</b> '
                    f'{escape(m.group(2))}</p>'
                )
            else:
                body_html.append(f'<p>{escape(text)}</p>')

    # Wrap consecutive <li> in <ul>
    out = []
    in_ul = False
    for line in body_html:
        if line.startswith("<li>"):
            if not in_ul:
                out.append('<ul>')
                in_ul = True
            out.append(line)
        else:
            if in_ul:
                out.append('</ul>')
                in_ul = False
            out.append(line)
    if in_ul:
        out.append('</ul>')

    body = "\n".join(out)
    nav = "\n".join(nav_html)
    now = datetime.now().strftime("%Y-%m-%d %H:%M")

    html = f"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PIXORA · DOCUMENTO MAESTRO · BRUTALIST</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;500;700;800&family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
:root {{
    --bg: #050308;
    --bg-2: #0a0612;
    --fg: #d8d8e0;
    --fg-dim: #707080;
    --neon: #c9ff44;
    --neon-dim: #6a8a30;
    --accent: #ff5544;
    --line: #1a1828;
    --code: #1a1a26;
}}
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
html {{ scroll-behavior: smooth; }}
body {{
    background: var(--bg);
    color: var(--fg);
    font-family: 'JetBrains Mono', monospace;
    font-size: 14px;
    line-height: 1.6;
    min-height: 100vh;
    background-image:
      linear-gradient(rgba(201,255,68,.025) 1px, transparent 1px),
      linear-gradient(90deg, rgba(201,255,68,.025) 1px, transparent 1px);
    background-size: 28px 28px;
}}

.layout {{
    display: grid;
    grid-template-columns: 320px 1fr;
    min-height: 100vh;
}}

/* ── SIDEBAR ──────────────────────────────────────── */
.sidebar {{
    background: var(--bg-2);
    border-right: 1px solid var(--line);
    padding: 24px 18px;
    position: sticky;
    top: 0;
    height: 100vh;
    overflow-y: auto;
}}
.sidebar::-webkit-scrollbar {{ width: 6px; }}
.sidebar::-webkit-scrollbar-track {{ background: var(--bg-2); }}
.sidebar::-webkit-scrollbar-thumb {{ background: var(--neon-dim); }}
.brand {{
    border-bottom: 1px dashed var(--neon);
    padding-bottom: 14px;
    margin-bottom: 18px;
}}
.brand .label {{
    font-size: 9px; letter-spacing: 0.4em;
    color: var(--neon);
    text-transform: uppercase;
    margin-bottom: 4px;
}}
.brand h1 {{
    font-family: 'Space Grotesk', sans-serif;
    font-weight: 700;
    font-size: 22px;
    color: #fff;
    text-transform: uppercase;
    letter-spacing: -0.02em;
    line-height: 1;
    margin-bottom: 6px;
}}
.brand .meta {{
    font-size: 10px;
    color: var(--fg-dim);
}}
.brand .meta b {{ color: var(--neon); }}

.nav {{
    font-size: 11px;
}}
.nav a {{
    display: block;
    color: var(--fg-dim);
    text-decoration: none;
    padding: 3px 0;
    line-height: 1.4;
    transition: color .15s;
}}
.nav a:hover {{ color: var(--neon); }}
.nav .nav-bar {{ color: var(--neon-dim); margin-right: 4px; }}
.nav .nav-l1 {{ color: #fff; font-weight: 700; margin-top: 12px; font-size: 12px; }}
.nav .nav-l2 {{ padding-left: 12px; }}
.nav .nav-l3 {{ padding-left: 24px; color: #5a5a64; font-size: 10px; }}
.nav .nav-l4 {{ padding-left: 36px; color: #4a4a54; font-size: 10px; }}

/* ── MAIN ─────────────────────────────────────────── */
.main {{
    padding: 36px 48px 80px;
    max-width: 980px;
}}

.banner {{
    border: 2px solid var(--neon);
    padding: 18px 22px;
    margin-bottom: 36px;
    position: relative;
}}
.banner::before, .banner::after {{
    content: '';
    position: absolute;
    width: 16px; height: 16px;
}}
.banner::before {{ top: -2px; left: -2px; border-top: 2px solid #fff; border-left: 2px solid #fff; }}
.banner::after {{ bottom: -2px; right: -2px; border-bottom: 2px solid #fff; border-right: 2px solid #fff; }}
.banner .stamp {{
    font-size: 9px;
    letter-spacing: 0.5em;
    color: var(--neon);
    text-transform: uppercase;
}}
.banner h1 {{
    font-family: 'Space Grotesk', sans-serif;
    font-weight: 700;
    font-size: 36px;
    color: #fff;
    text-transform: uppercase;
    letter-spacing: -0.02em;
    margin: 6px 0;
}}
.banner .specs {{
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 12px;
    margin-top: 14px;
    border-top: 1px dashed var(--neon);
    padding-top: 14px;
}}
.banner .specs div {{ font-size: 10px; color: var(--fg-dim); }}
.banner .specs b {{ color: var(--neon); display: block; font-size: 9px; letter-spacing: 0.2em; text-transform: uppercase; margin-bottom: 2px; }}

/* Headings */
.hd-l1 {{
    font-family: 'Space Grotesk', sans-serif;
    font-weight: 800;
    font-size: 32px;
    color: #fff;
    text-transform: uppercase;
    margin: 60px 0 16px;
    padding: 12px 0;
    border-top: 4px solid var(--neon);
    border-bottom: 1px solid var(--line);
    letter-spacing: -0.02em;
    line-height: 1.05;
}}
.hd-l2 {{
    font-family: 'Space Grotesk', sans-serif;
    font-weight: 700;
    font-size: 22px;
    color: var(--neon);
    text-transform: uppercase;
    margin: 36px 0 12px;
    padding-left: 12px;
    border-left: 4px solid var(--neon);
    letter-spacing: -0.01em;
    line-height: 1.1;
}}
.hd-l3 {{
    font-family: 'Space Grotesk', sans-serif;
    font-weight: 600;
    font-size: 16px;
    color: #fff;
    text-transform: uppercase;
    margin: 26px 0 8px;
    letter-spacing: 0.01em;
}}
.hd-l4 {{
    font-family: 'JetBrains Mono', monospace;
    font-weight: 500;
    font-size: 13px;
    color: var(--neon-dim);
    text-transform: uppercase;
    margin: 18px 0 6px;
    letter-spacing: 0.04em;
}}
.hd-marker {{
    color: var(--neon);
    font-weight: 700;
    margin-right: 8px;
    font-family: 'JetBrains Mono', monospace;
    opacity: 0.6;
}}

/* Body */
p {{
    margin-bottom: 12px;
    color: var(--fg);
    font-size: 13px;
}}
p.kv {{
    border-left: 2px solid var(--neon-dim);
    padding-left: 12px;
    margin-bottom: 10px;
    font-size: 12px;
}}
p.kv b {{ color: var(--neon); text-transform: uppercase; letter-spacing: 0.05em; }}

ul {{
    list-style: none;
    margin: 8px 0 16px;
    padding-left: 0;
}}
li {{
    color: var(--fg);
    font-size: 12.5px;
    padding: 4px 0 4px 22px;
    position: relative;
    line-height: 1.5;
}}
li::before {{
    content: '> ';
    position: absolute;
    left: 0;
    color: var(--neon);
    font-weight: 700;
}}

pre.quote {{
    background: var(--code);
    color: var(--neon);
    padding: 12px 14px;
    border-left: 3px solid var(--neon);
    margin: 12px 0;
    font-size: 12px;
    overflow-x: auto;
    white-space: pre-wrap;
}}

/* Footer ASCII signature */
.foot {{
    margin-top: 80px;
    padding-top: 24px;
    border-top: 1px dashed var(--neon-dim);
    text-align: center;
    font-size: 10px;
    color: var(--fg-dim);
    line-height: 1.4;
}}
.foot pre {{
    color: var(--neon-dim);
    font-size: 8px;
    line-height: 1.1;
    margin-bottom: 12px;
}}

@media (max-width: 900px) {{
    .layout {{ grid-template-columns: 1fr; }}
    .sidebar {{ position: relative; height: auto; max-height: 40vh; }}
    .main {{ padding: 24px 20px 60px; }}
    .banner h1 {{ font-size: 24px; }}
    .banner .specs {{ grid-template-columns: 1fr 1fr; }}
}}
</style>
</head>
<body>

<div class="layout">

  <aside class="sidebar">
    <div class="brand">
      <div class="label">// SYSTEM_DOC</div>
      <h1>PIXORA<br>MASTER</h1>
      <div class="meta">
        <b>BUILD</b> {now}<br>
        <b>FORMAT</b> brutalist_tech_v1<br>
        <b>SOURCE</b> docx → html
      </div>
    </div>
    <nav class="nav">
{nav}
    </nav>
  </aside>

  <main class="main">
    <div class="banner">
      <div class="stamp">// SYSTEM_RECORD · CONFIDENTIAL · ORBIX_INTERNAL</div>
      <h1>Pixora_IA<br>Documento_Maestro</h1>
      <div class="specs">
        <div><b>VERSION</b>1.6.5+41</div>
        <div><b>BUILD_DATE</b>{now}</div>
        <div><b>FORMAT</b>html_brutalist</div>
        <div><b>OWNER</b>Eduardo / Orbix</div>
      </div>
    </div>

{body}

    <div class="foot">
      <pre>
   .--..--..--..--..--..--..--..--..--.
  / .. \\.. \\.. \\.. \\.. \\.. \\.. \\.. \\.. \\
  \\ \\/\\ `'\\ `'\\ `'\\ `'\\ `'\\ `'\\ `'\\ `'\\
   \\/ /`--'`--'`--'`--'`--'`--'`--'`--'
   `--'
      </pre>
      PIXORA · MASTER DOC · BRUTALIST EDITION · BUILD {now} · END_OF_FILE
    </div>
  </main>

</div>

</body>
</html>"""

    out_file = OUT_DIR / "index.html"
    out_file.write_text(html, encoding="utf-8")
    print(f"OK rendered {len(used_ids)} sections")
    print(f"   {len(body_html)} body blocks")
    print(f"   {out_file.stat().st_size:,} bytes")
    print(f"   {out_file}")


if __name__ == "__main__":
    render()
