# -*- coding: utf-8 -*-
"""Re-sube la descripción de Alicia con acentos correctos + markup de highlights."""
import json, re, urllib.request
from pathlib import Path

SK = re.search(r'Service Role Key[^\n]*?(eyJ[A-Za-z0-9_\-\.]+)',
               Path(r'D:/Orbix/Pixora-IA/KEYS_LOCAL.md').read_text(encoding='utf-8')).group(1)
P = 'https://vzuwvsmlyigjtsearxym.supabase.co'

DESC = (
    "[[name:Alicia]] es la niña más [[emotion:curiosa]] de la literatura. Una tarde, "
    "aburrida junto al río, ve pasar a un [[name:Conejo Blanco]] con chaleco y reloj de "
    "bolsillo, y lo sigue por su [[place:madriguera]] hasta caer en el "
    "[[place:País de las Maravillas]]: un mundo donde la [[power:lógica se invierte]]. Ahí "
    "bebe pociones que la [[power:encogen]], come pasteles que la [[power:agigantan]] y "
    "conversa con el enigmático [[name:Gato de Cheshire]], que aparece y desaparece dejando "
    "flotando solo su [[emotion:sonrisa]]. Creada por [[name:Lewis Carroll]] en 1865, su "
    "viaje es puro [[power:sinsentido]] y pura [[emotion:maravilla]] — un sueño del que "
    "nadie quiere despertar."
)


def put_json(b, r, d):
    body = json.dumps(d, indent=2, ensure_ascii=False).encode('utf-8')
    req = urllib.request.Request(f'{P}/storage/v1/object/{b}/{r}', data=body, method='PUT')
    req.add_header('Authorization', 'Bearer ' + SK)
    req.add_header('Content-Type', 'application/json')
    req.add_header('x-upsert', 'true')
    return urllib.request.urlopen(req, timeout=30).status


def get_json(b, r):
    return json.load(urllib.request.urlopen(f'{P}/storage/v1/object/public/{b}/{r}', timeout=15))


cat = get_json('wallpaper-images', 'catalog_index.json')
for it in cat.get('items', []):
    if it.get('id') == 'alicia_wonderland':
        it['description'] = DESC
        print(f"description actualizada ({len(DESC)} chars, con acentos)")
cat['version'] = (cat.get('version', 0) or 0) + 1
print('catalog ->', cat['version'], put_json('wallpaper-images', 'catalog_index.json', cat))
