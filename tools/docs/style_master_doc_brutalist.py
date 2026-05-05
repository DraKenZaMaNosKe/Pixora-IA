"""
Re-style the Pixora Master Document with a Brutalist Tech aesthetic
suitable for Drive web / Google Docs viewer.

Approach: iterate the existing .docx paragraphs, classify each one
(heading level, body, key-value, list, code), and rewrite with custom
runs (font name, color, weight). Builds a NEW document so styling is
clean — preserves ALL content but discards messy historical formatting.

Run: python tools/docs/style_master_doc_brutalist.py

Output:
  - Snapshot of the original copied to docs/master_doc_snapshots/
  - The .docx at G:/Mi unidad/.../Pixora_IA_Documento_Maestro.docx
    is REPLACED with the styled version.
"""
from __future__ import annotations
import hashlib
import re
import shutil
import sys
from datetime import date, datetime
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

from docx import Document
from docx.shared import Pt, RGBColor, Inches, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_ALIGN_VERTICAL
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

SRC = Path(r"G:/Mi unidad/pixoraIA_admin/admin/administracion/Pixora_IA_Documento_Maestro.docx")
SNAP_DIR = Path(r"D:/Orbix/Pixora-IA/docs/master_doc_snapshots")

# Brutalist Tech palette (dark accents on white paper)
NEON_GREEN  = RGBColor(0x1a, 0x6e, 0x1a)  # accents, mono labels — readable on white
DARK_GREEN  = RGBColor(0x0a, 0x44, 0x0a)  # H1 darker
INK         = RGBColor(0x1a, 0x1a, 0x1a)  # body text
DIM_INK     = RGBColor(0x6a, 0x6a, 0x70)  # secondary
ACCENT_RED  = RGBColor(0xcc, 0x22, 0x44)  # warnings / pitfalls
CODE_BG_HEX = "1a1a26"                    # dark code block fill
CODE_TEXT   = RGBColor(0xc9, 0xff, 0x44)  # light neon green text on dark
NEUTRAL_BG_HEX = "f0f0f5"                 # subtle gray for stat tables

MONO   = "Consolas"
MONO2  = "Cascadia Code"
SERIF  = "Aptos"
DISPLAY = "Aptos"  # Word's default modern serif-ish; keeps it portable

# Patterns used to classify body lines
KV_RE = re.compile(r"^([A-ZÁÉÍÓÚÑ][^:]{0,40}):\s+(.+)$")
CODE_LINE_RE = re.compile(r"^(?:adb |python |flutter |gradle |git |curl |bash |sh |ffmpeg )")


def shade_cell(cell, fill_hex: str):
    """Set background fill on a table cell."""
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), fill_hex)
    tc_pr.append(shd)


def add_horizontal_line(doc, color_hex: str = "1a6e1a"):
    """Insert a horizontal divider line via empty paragraph + bottom border."""
    p = doc.add_paragraph()
    pPr = p._p.get_or_add_pPr()
    pBdr = OxmlElement("w:pBdr")
    bottom = OxmlElement("w:bottom")
    bottom.set(qn("w:val"), "single")
    bottom.set(qn("w:sz"), "12")
    bottom.set(qn("w:space"), "1")
    bottom.set(qn("w:color"), color_hex)
    pBdr.append(bottom)
    pPr.append(pBdr)


def set_run(run, *, name=None, size=None, bold=False, italic=False,
            color=None, mono=False, upper=False):
    if mono:
        run.font.name = MONO
        # Apply East Asian font fallback so non-ASCII chars stay mono too
        rPr = run._r.get_or_add_rPr()
        rFonts = rPr.find(qn("w:rFonts"))
        if rFonts is None:
            rFonts = OxmlElement("w:rFonts")
            rPr.append(rFonts)
        rFonts.set(qn("w:ascii"), MONO)
        rFonts.set(qn("w:hAnsi"), MONO)
        rFonts.set(qn("w:cs"), MONO)
    elif name:
        run.font.name = name
    if size:
        run.font.size = Pt(size)
    if bold:
        run.bold = True
    if italic:
        run.italic = True
    if color is not None:
        run.font.color.rgb = color
    if upper:
        run.text = run.text.upper()


def set_paragraph_spacing(p, before=0, after=0, line=1.15):
    pf = p.paragraph_format
    pf.space_before = Pt(before)
    pf.space_after = Pt(after)
    pf.line_spacing = line


def write_title_banner(doc, version_str: str):
    """Big terminal-style banner at the top of the document."""
    # Stamp / kicker
    p = doc.add_paragraph()
    set_paragraph_spacing(p, before=0, after=2)
    r = p.add_run("// SYSTEM_RECORD · CONFIDENTIAL · ORBIX_INTERNAL")
    set_run(r, mono=True, size=9, bold=True, color=NEON_GREEN)

    # Big title — two lines
    p = doc.add_paragraph()
    set_paragraph_spacing(p, before=4, after=2)
    r = p.add_run("PIXORA_IA")
    set_run(r, name=DISPLAY, size=36, bold=True, color=INK)

    p = doc.add_paragraph()
    set_paragraph_spacing(p, before=0, after=4)
    r = p.add_run("DOCUMENTO_MAESTRO")
    set_run(r, name=DISPLAY, size=36, bold=True, color=NEON_GREEN)

    # Spec table — 4 columns
    table = doc.add_table(rows=2, cols=4)
    table.autofit = True
    headers = ("VERSION", "BUILD_DATE", "FORMAT", "OWNER")
    values = (version_str, date.today().isoformat(), "brutalist_v1", "Eduardo / Orbix")
    for i, (h, v) in enumerate(zip(headers, values)):
        # Header
        hcell = table.rows[0].cells[i]
        hp = hcell.paragraphs[0]
        hp.paragraph_format.space_before = Pt(0)
        hp.paragraph_format.space_after = Pt(0)
        hr = hp.add_run(h)
        set_run(hr, mono=True, size=8, bold=True, color=NEON_GREEN)
        shade_cell(hcell, NEUTRAL_BG_HEX)
        # Value
        vcell = table.rows[1].cells[i]
        vp = vcell.paragraphs[0]
        vp.paragraph_format.space_before = Pt(0)
        vp.paragraph_format.space_after = Pt(0)
        vr = vp.add_run(v)
        set_run(vr, mono=True, size=11, bold=True, color=INK)
        shade_cell(vcell, "ffffff")

    add_horizontal_line(doc, "1a6e1a")
    doc.add_paragraph()


def write_heading(doc, text: str, level: int):
    p = doc.add_paragraph()
    if level == 1:
        set_paragraph_spacing(p, before=24, after=8)
        # Top border
        pPr = p._p.get_or_add_pPr()
        pBdr = OxmlElement("w:pBdr")
        top = OxmlElement("w:top")
        top.set(qn("w:val"), "single")
        top.set(qn("w:sz"), "24")
        top.set(qn("w:color"), "1a6e1a")
        pBdr.append(top)
        pPr.append(pBdr)
        r = p.add_run(f"## {text.upper()}")
        set_run(r, name=DISPLAY, size=22, bold=True, color=DARK_GREEN)
    elif level == 2:
        set_paragraph_spacing(p, before=18, after=6)
        r = p.add_run(f"▸ {text}")
        set_run(r, name=DISPLAY, size=15, bold=True, color=NEON_GREEN)
    elif level == 3:
        set_paragraph_spacing(p, before=12, after=4)
        r = p.add_run(text)
        set_run(r, name=DISPLAY, size=12, bold=True, color=INK)
    else:  # level 4+
        set_paragraph_spacing(p, before=8, after=2)
        r = p.add_run(f"// {text.upper()}")
        set_run(r, mono=True, size=10, bold=True, color=DIM_INK)


def write_kv(doc, label: str, value: str):
    """Key-value paragraph styled like a spec entry."""
    p = doc.add_paragraph()
    set_paragraph_spacing(p, before=2, after=2, line=1.3)
    # Left border
    pPr = p._p.get_or_add_pPr()
    pBdr = OxmlElement("w:pBdr")
    left = OxmlElement("w:left")
    left.set(qn("w:val"), "single")
    left.set(qn("w:sz"), "16")
    left.set(qn("w:color"), "1a6e1a")
    left.set(qn("w:space"), "8")
    pBdr.append(left)
    pPr.append(pBdr)
    pf = p.paragraph_format
    pf.left_indent = Cm(0.3)

    rl = p.add_run(label.upper() + ": ")
    set_run(rl, mono=True, size=10, bold=True, color=NEON_GREEN)
    rv = p.add_run(value)
    set_run(rv, name=SERIF, size=11, color=INK)


def write_bullet(doc, text: str):
    p = doc.add_paragraph()
    set_paragraph_spacing(p, before=0, after=2, line=1.3)
    pf = p.paragraph_format
    pf.left_indent = Cm(0.6)

    rb = p.add_run("> ")
    set_run(rb, mono=True, size=11, bold=True, color=NEON_GREEN)
    rt = p.add_run(text)
    set_run(rt, name=SERIF, size=11, color=INK)


def write_code_block(doc, text: str):
    """Single-cell table with dark background and light mono text."""
    table = doc.add_table(rows=1, cols=1)
    table.autofit = True
    cell = table.rows[0].cells[0]
    shade_cell(cell, CODE_BG_HEX)
    p = cell.paragraphs[0]
    set_paragraph_spacing(p, before=2, after=2)
    r = p.add_run(text)
    set_run(r, mono=True, size=10, color=CODE_TEXT)


def write_body(doc, text: str):
    p = doc.add_paragraph()
    set_paragraph_spacing(p, before=0, after=4, line=1.4)
    r = p.add_run(text)
    set_run(r, name=SERIF, size=11, color=INK)


def write_quote(doc, text: str):
    """Dark-bg code-like block for quotes/raw text."""
    write_code_block(doc, text)


def write_footer(doc):
    add_horizontal_line(doc, "1a6e1a")
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    set_paragraph_spacing(p, before=8, after=0)
    r = p.add_run(f"PIXORA · MASTER DOC · BRUTALIST EDITION · BUILD {datetime.now():%Y-%m-%d %H:%M} · END_OF_FILE")
    set_run(r, mono=True, size=8, color=DIM_INK)


def main():
    if not SRC.exists():
        raise SystemExit(f"NOT FOUND: {SRC}")

    # Snapshot
    SNAP_DIR.mkdir(parents=True, exist_ok=True)
    sha8 = hashlib.sha256(SRC.read_bytes()).hexdigest()[:8]
    snap = SNAP_DIR / f"{date.today().isoformat()}_{sha8}_pre-restyle.docx"
    if not snap.exists():
        shutil.copy2(SRC, snap)
        print(f"Snapshot: {snap.name}")

    # Read source content (text + heading levels only)
    src_doc = Document(str(SRC))
    paragraphs = []
    for p in src_doc.paragraphs:
        text = p.text.strip()
        if not text:
            continue
        style = p.style.name
        level = None
        if style == "Title":
            level = 1
        elif style.startswith("Heading"):
            try:
                level = int(style.replace("Heading ", ""))
            except ValueError:
                level = 2
        kind = "heading" if level else "list" if style == "List Bullet" else "quote" if style == "Quote" else "body"
        paragraphs.append({
            "kind": kind,
            "level": level,
            "text": text,
            "style": style,
        })
    print(f"Read {len(paragraphs)} non-empty paragraphs from source")

    # Build new doc
    new_doc = Document()
    # Default style — light spacing, body font
    sty = new_doc.styles["Normal"]
    sty.font.name = SERIF
    sty.font.size = Pt(11)
    sty.font.color.rgb = INK

    # Page margins — slightly narrower for tech vibe
    for section in new_doc.sections:
        section.left_margin = Cm(2.0)
        section.right_margin = Cm(2.0)
        section.top_margin = Cm(2.0)
        section.bottom_margin = Cm(2.0)

    # Find current version from paragraphs (look for v1.X.Y pattern in headings)
    version_str = "1.6.5+41"
    for p in paragraphs:
        if p["kind"] == "heading":
            m = re.search(r"v(\d+\.\d+\.\d+(?:\+\d+)?)", p["text"])
            if m:
                version_str = m.group(1)
                break

    write_title_banner(new_doc, version_str)

    # Now write all paragraphs with style
    for p in paragraphs:
        text = p["text"]
        if p["kind"] == "heading":
            write_heading(new_doc, text, p["level"] or 2)
        elif p["kind"] == "list":
            write_bullet(new_doc, text)
        elif p["kind"] == "quote":
            write_quote(new_doc, text)
        else:  # body
            # Heuristic: detect KV pattern "Label: value"
            m = KV_RE.match(text)
            if m and len(m.group(1)) <= 30:
                write_kv(new_doc, m.group(1), m.group(2))
            elif CODE_LINE_RE.match(text):
                write_code_block(new_doc, text)
            else:
                write_body(new_doc, text)

    write_footer(new_doc)

    new_doc.save(str(SRC))
    print(f"OK saved restyled doc -> {SRC}")
    print(f"   Body blocks written: {len(paragraphs)}")
    print(f"   File size: {SRC.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
