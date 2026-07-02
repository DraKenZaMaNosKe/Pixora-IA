"""Generic Freesound audition tool — toma un config JSON y arma HTML
de selección. Permite multi-select por slot. Botón export JSON (sin
abrir tabs raros — `type="button"` explícito y evento bloqueado).

Uso:
   python audition.py audition_videogames.json
   python audition.py audition_movies.json
   python audition.py audition_sfx.json

Cada config tiene:
  - title: nombre del pack
  - slots: lista de {id, name, hint, query, duration_target}
"""
import argparse
import json
import re
import sys
import webbrowser
from pathlib import Path
from urllib.parse import quote

import requests

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

KEYS = Path(r"D:/Orbix/Pixora-IA/KEYS_LOCAL.md")
ROOT = Path(__file__).parent
OUT_DIR = Path(r"D:/Orbix/Pixora-IA/docs/design")
OUT_DIR.mkdir(parents=True, exist_ok=True)

API = "https://freesound.org/apiv2"


def load_token() -> str:
    text = KEYS.read_text(encoding="utf-8")
    m = re.search(r"API Key \(client secret\):\s*(\S+)", text)
    if not m:
        sys.exit("Could not find Freesound API key")
    return m.group(1)


def search_top_n(token: str, query: str, n: int = 6) -> list[dict]:
    params = {
        "query": query,
        "filter": '(license:"Creative Commons 0" OR license:"Attribution") duration:[0.3 TO 30]',
        "sort": "rating_desc",
        "fields": "id,name,duration,license,previews,username,avg_rating,tags,description",
        "page_size": n,
        "token": token,
    }
    r = requests.get(f"{API}/search/text/", params=params, timeout=30)
    if r.status_code != 200:
        return []
    return r.json().get("results", [])


def gen_html(title: str, token: str, slots_results: list[tuple[dict, list[dict]]]) -> str:
    rows_html = []
    for slot, hits in slots_results:
        cards = []
        for h in hits:
            preview_url = h.get("previews", {}).get("preview-hq-mp3", "")
            if preview_url:
                preview_url = f"{preview_url}?token={quote(token)}"
            else:
                continue
            tags = ", ".join((h.get("tags") or [])[:5])
            desc = (h.get("description") or "")[:140].replace("\n", " ").replace('"', "&quot;")
            cards.append(f"""
<div class="cand">
  <label class="pick">
    <input type="checkbox" data-slot="{slot['id']}" data-fsid="{h['id']}"
           data-name="{h['name'].replace('"','&quot;')[:60]}"
           data-dur="{h['duration']:.1f}" data-user="{h.get('username','?')}">
    <span class="pick-mark">✓</span>
  </label>
  <div class="meta">
    <div class="cand-name">{h['name'][:60]}</div>
    <div class="cand-info">
      ⏱ {h['duration']:.1f}s · ⭐ {h.get('avg_rating', 0):.1f}/5 ·
      by {h.get('username', '?')}
    </div>
    <div class="cand-tags">{tags}</div>
    <div class="cand-desc">{desc}</div>
  </div>
  <audio controls preload="none" src="{preview_url}"></audio>
</div>""")
        rows_html.append(f"""
<section class="slot" data-slot-id="{slot['id']}">
  <header>
    <h2>{slot['name']} <span class="count zero" id="count_{slot['id']}">0 elegidos</span></h2>
    <div class="slot-meta">
      <code>{slot['id']}</code> · target {slot['duration_target']} ·
      query: <em>"{slot['query']}"</em>
    </div>
    <div class="hint">{slot.get('hint', '')}</div>
  </header>
  <div class="cards">
    {''.join(cards) if cards else '<div class="no-results">Sin resultados</div>'}
  </div>
</section>
""")

    return """<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>""" + title + """ · Audition</title>
<style>
  :root {
    --bg: #0F0E1A;
    --surf: #1A1B2E;
    --surf2: #21223A;
    --text: #E8E8EC;
    --muted: #98989D;
    --cyan: #00F0FF;
    --gold: #E6B655;
    --pink: #FF2BD6;
    --border: #2C2C3E;
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--text);
    font-family: -apple-system, 'Segoe UI', sans-serif; line-height: 1.5; }
  header.top { background: linear-gradient(180deg, #1A0033 0%, #0F0E1A 100%);
    padding: 28px 32px 20px; border-bottom: 1px solid var(--border);
    position: sticky; top: 0; z-index: 10; backdrop-filter: blur(8px); }
  h1 { margin: 0 0 4px; font-size: 28px; color: var(--cyan); letter-spacing: 1px; }
  .subtitle { color: var(--muted); font-size: 14px; }
  main { max-width: 980px; margin: 0 auto; padding: 24px 32px 80px; }
  .slot { background: var(--surf); border: 1px solid var(--border);
    border-radius: 12px; padding: 20px; margin: 18px 0; }
  .slot header { margin-bottom: 14px; }
  .slot h2 { margin: 0 0 4px; color: var(--gold); font-size: 18px; }
  .slot-meta { color: var(--muted); font-size: 12px; font-family: monospace; }
  .hint { color: var(--text); font-size: 13px; margin-top: 6px; font-style: italic; opacity: 0.8; }
  .cards { display: flex; flex-direction: column; gap: 10px; margin: 14px 0; }
  .cand { display: grid; grid-template-columns: 36px 1fr 240px; gap: 12px;
    align-items: center; background: var(--surf2); border: 1px solid var(--border);
    border-radius: 8px; padding: 10px 12px; transition: border-color .2s; }
  .cand:has(input:checked) { border-color: var(--cyan); box-shadow: 0 0 0 1px var(--cyan); }
  .pick { cursor: pointer; display: flex; align-items: center; justify-content: center; }
  .pick input { display: none; }
  .pick-mark { width: 30px; height: 30px; border-radius: 8px; border: 2px solid var(--muted);
    display: flex; align-items: center; justify-content: center;
    font-size: 14px; font-weight: bold; color: transparent; transition: all .2s; }
  .pick input:checked + .pick-mark { border-color: var(--cyan); background: var(--cyan);
    color: var(--bg); transform: scale(1.1); }
  .count { background: var(--bg); color: var(--cyan); padding: 2px 10px;
    border-radius: 12px; font-size: 11px; font-weight: 400; margin-left: 12px;
    border: 1px solid var(--cyan); }
  .count.zero { color: var(--muted); border-color: var(--muted); }
  .meta { min-width: 0; }
  .cand-name { font-weight: 600; color: var(--text); margin-bottom: 2px; }
  .cand-info { color: var(--muted); font-size: 12px; }
  .cand-tags { color: var(--gold); font-size: 11px; margin-top: 4px; font-family: monospace; opacity: 0.6; }
  .cand-desc { color: var(--text); font-size: 11px; margin-top: 4px; opacity: 0.6; max-height: 30px; overflow: hidden; }
  audio { width: 240px; height: 36px; }
  .no-results { color: #C2410C; padding: 20px; text-align: center; }
  .actions { position: sticky; bottom: 0; background: var(--surf); border: 1px solid var(--cyan);
    border-radius: 12px; padding: 16px; margin-top: 24px;
    display: flex; gap: 12px; align-items: center; }
  button { background: var(--cyan); color: var(--bg); border: none; padding: 12px 24px;
    border-radius: 8px; font-weight: 700; cursor: pointer; font-size: 14px;
    /* type=button por default sin form, pero forzamos no-submit */ }
  button:hover { background: #00d0e0; }
  #output { flex: 1; background: var(--bg); color: var(--cyan); padding: 10px;
    border-radius: 6px; font-family: monospace; font-size: 11px; max-height: 240px;
    overflow: auto; white-space: pre-wrap; border: 1px solid var(--border); }
</style>
</head>
<body>
<header class="top">
  <h1>""" + title + """</h1>
  <div class="subtitle">
    Escucha cada candidato y marca los que más te gusten (puedes elegir varios por slot).
    Solo CC0 / CC-BY (uso libre comercial).
  </div>
</header>
<main>
""" + "\n".join(rows_html) + """
<div class="actions">
  <button type="button" onclick="generateJSON(); return false;">✓ Generar JSON</button>
  <pre id="output">(marca arriba y haz click)</pre>
  <button type="button" onclick="copyOutput(); return false;" style="background:var(--gold);">📋 Copiar</button>
</div>
</main>
<script>
// Prevenir navegación accidental por iframes audio o forms huérfanos
window.addEventListener('beforeunload', e => {
  if (window._allowExit) return;
  const hasChecks = document.querySelector('input[type=checkbox]:checked');
  if (hasChecks) {
    e.preventDefault();
    e.returnValue = '';
  }
});

function updateCounts() {
  document.querySelectorAll('.slot').forEach(slot => {
    const id = slot.dataset.slotId;
    const n = slot.querySelectorAll('input[type=checkbox]:checked').length;
    const badge = document.getElementById('count_' + id);
    if (badge) {
      badge.textContent = n === 0 ? '0 elegidos' : (n + ' elegido' + (n > 1 ? 's' : ''));
      badge.classList.toggle('zero', n === 0);
    }
  });
}
document.addEventListener('change', e => {
  if (e.target.matches('input[type=checkbox][data-slot]')) updateCounts();
});
window.addEventListener('load', updateCounts);

function generateJSON() {
  const bySlot = {};
  document.querySelectorAll('input[type=checkbox][data-slot]:checked').forEach(cb => {
    const slot = cb.dataset.slot;
    if (!bySlot[slot]) bySlot[slot] = [];
    bySlot[slot].push({
      freesound_id: parseInt(cb.dataset.fsid),
      name: cb.dataset.name,
      duration: parseFloat(cb.dataset.dur),
      user: cb.dataset.user
    });
  });
  const ordered = {};
  document.querySelectorAll('.slot').forEach(s => {
    const id = s.dataset.slotId;
    ordered[id] = bySlot[id] || [];
  });
  const total = Object.values(ordered).reduce((a,b) => a + b.length, 0);
  const json = JSON.stringify(ordered, null, 2);
  document.getElementById('output').textContent =
    `// ${total} tonos en ${Object.keys(ordered).filter(k => ordered[k].length > 0).length} slots\n` + json;
  return false;
}
function copyOutput() {
  const text = document.getElementById('output').textContent;
  if (!text || text.startsWith('(')) { alert('Primero "Generar JSON"'); return false; }
  navigator.clipboard.writeText(text).then(() => alert('✓ Copiado'));
  return false;
}
</script>
</body>
</html>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("config_json")
    args = ap.parse_args()

    cfg = json.loads(Path(args.config_json).read_text(encoding="utf-8"))
    title = cfg.get("title", "Audition")
    slots = cfg["slots"]
    out_name = Path(args.config_json).stem + ".html"
    out_path = OUT_DIR / out_name

    token = load_token()
    print(f"Cargados {len(slots)} slots para '{title}'")
    results = []
    for s in slots:
        print(f"  · {s['id']:35s} q='{s['query']}'", end=" ")
        hits = search_top_n(token, s["query"], n=6)
        print(f"→ {len(hits)} resultados")
        results.append((s, hits))

    html = gen_html(title, token, results)
    out_path.write_text(html, encoding="utf-8")
    print(f"\n[OK] {out_path}")
    print("Abriendo en navegador...")
    webbrowser.open(out_path.as_uri())


if __name__ == "__main__":
    main()
