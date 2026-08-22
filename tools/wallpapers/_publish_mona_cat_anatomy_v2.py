"""Republica Mona Lisa tras corrección anatómica y QA Huawei."""
from __future__ import annotations
import json, sys
from datetime import datetime, timezone
from pathlib import Path

HERE=Path(__file__).resolve().parent
sys.path[:0]=[str(HERE),str(HERE.parent)]
from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET,SCENES_BUCKET,get_json,put_json

SID="mona_lisa_gatito_museo"; KEY="mona_lisa_gatito_museo_pair_v2"
ROOT=Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/mona_lisa_gatito_museo_20260818")
QA=ROOT/"qa/HUAWEI_ANATOMY_V2_QA.png"
BEFORE=263; AFTER=264

def close(v,e): return abs(float(v)-e)<=.001
def validate(spec, published):
    if spec.get("id")!=SID or bool(spec.get("published")) is not published: raise RuntimeError("Estado spec inesperado")
    layers=spec.get("image_layers") or []; sprites=spec.get("sprites") or []
    if len(layers)!=1 or layers[0].get("key")!="background" or int(layers[0].get("revision",0))!=3 or not close(layers[0].get("scale",0),1.26): raise RuntimeError("Fondo cambió")
    if len(sprites)!=1: raise RuntimeError("Sprite inesperado")
    s=sprites[0]; p=s.get("params") or {}
    if s.get("manifest_key")!=KEY or s.get("behavior")!="static" or not close(s.get("frame_skip",0),10): raise RuntimeError("Animación cambió")
    expected={"x":.5,"y":.61,"scale":.00078,"parallax_factor":.16}
    if any(not close(p.get(k,-1),v) for k,v in expected.items()): raise RuntimeError("Geometría/parallax cambió")

def main():
    spec=get_json(SCENES_BUCKET,f"{SID}.json"); validate(spec,False)
    cat=get_json(IMG_BUCKET,"catalog_index.json")
    if int(cat.get("version",0))!=BEFORE: raise RuntimeError("Versión catálogo cambió")
    matches=[i for i in cat.get("items",[]) if i.get("id")==SID]
    if len(matches)!=1 or matches[0].get("published") is not False: raise RuntimeError("Catálogo no parte oculto")
    manifest=get_json("wallpaper-sprites","manifest.json"); pack=manifest.get(KEY) or {}
    if int(pack.get("frames",0))!=5 or int(pack.get("size",0))!=6702749: raise RuntimeError("Pack V2 cambió")
    qas=[QA]+[ROOT/f"qa/HUAWEI_ANATOMY_V2_BLINK_{i}.png" for i in range(1,6)]
    if any(not p.is_file() or p.stat().st_size<100000 for p in qas): raise RuntimeError("Falta QA Huawei")
    outputs=[ROOT/"SCENE_SPEC_PRODUCTION_ANATOMY_V2.json",ROOT/"PRODUCTION_RECEIPT_ANATOMY_V2.json"]
    backups={p:p.read_bytes() if p.exists() else None for p in outputs}
    sb=json.loads(json.dumps(spec)); cb=json.loads(json.dumps(cat))
    conn=connect(); cur=conn.cursor(); cur.execute("SELECT published FROM wallpapers WHERE id=%s",(SID,)); row=cur.fetchone()
    if not row or bool(row[0]) is not False: cur.close();conn.close();raise RuntimeError("DB no parte oculto")
    try:
        spec["published"]=True; matches[0]["published"]=True; cat["version"]=AFTER
        put_json(SCENES_BUCKET,f"{SID}.json",spec); put_json(IMG_BUCKET,"catalog_index.json",cat)
        cur.execute("UPDATE wallpapers SET published=true WHERE id=%s RETURNING published",(SID,))
        if cur.fetchone()!=(True,): raise RuntimeError("DB no publicó")
        conn.commit()
        if not send_catalog_invalidate("wallpapers"): raise RuntimeError("FCM falló")
        rs=get_json(SCENES_BUCKET,f"{SID}.json"); validate(rs,True)
        rc=get_json(IMG_BUCKET,"catalog_index.json"); rm=[i for i in rc.get("items",[]) if i.get("id")==SID]
        cur.execute("SELECT published FROM wallpapers WHERE id=%s",(SID,)); rd=cur.fetchone()
        if int(rc.get("version",0))!=AFTER or len(rm)!=1 or rm[0].get("published") is not True or rd!=(True,): raise RuntimeError("Verificación triple falló")
        receipt={"scene_id":SID,"published_at":datetime.now(timezone.utc).isoformat(),"catalog_version":AFTER,"triple_published":True,"manifest_key":KEY,"frames":5,"anatomy":{"front_legs":2,"hind_legs":2,"total_legs":4},"qa_device":"HUAWEI VNS-L53","qa_captures":[str(p.relative_to(ROOT)).replace('\\','/') for p in qas],"fcm_catalog_invalidate":True}
        outputs[0].write_text(json.dumps(rs,ensure_ascii=False,indent=2)+"\n",encoding="utf-8"); outputs[1].write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    except Exception:
        original=sys.exc_info()[1]; conn.rollback(); put_json(SCENES_BUCKET,f"{SID}.json",sb); put_json(IMG_BUCKET,"catalog_index.json",cb)
        cur.execute("UPDATE wallpapers SET published=false WHERE id=%s",(SID,)); conn.commit()
        for p,b in backups.items():
            if b is None:
                if p.exists(): p.unlink()
            else: p.write_bytes(b)
        try: send_catalog_invalidate("wallpapers")
        except Exception: pass
        cur.close();conn.close();raise original
    cur.close();conn.close();print(json.dumps(receipt,ensure_ascii=False,indent=2))

if __name__=="__main__": main()
