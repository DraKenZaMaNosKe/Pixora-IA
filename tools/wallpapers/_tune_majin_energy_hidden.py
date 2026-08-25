"""Add a controlled violet energy pulse to the hidden Majin Buu scene."""
import io, json, sys
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

HERE=Path(__file__).resolve().parent; sys.path[:0]=[str(HERE),str(HERE.parent)]
from _upload_scene_generic import IMG_BUCKET,PROJECT,SCENES_BUCKET,get_json,put,put_json

SID="majin_buu_tormenta_violeta_depth"; STATIC_ID="majin_buu_tormenta_violeta_static"
ROOT=Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/majin_buu_tormenta_violeta_20260824")
MASTER=ROOT/"production/majin_buu_tormenta_violeta_1080x2340.png"; SPRITES=ROOT/"sprites"; QA=ROOT/"qa"; SIZE=(1080,2340)
PHASES=(0.35,0.65,1.0,0.65)

def url(name): return f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{name}"
def enc(im,q): out=io.BytesIO(); im.save(out,"WEBP",quality=q,method=6); return out.getvalue()
def frame(i,p):
    layer=Image.new("RGBA",SIZE,(0,0,0,0)); glow=Image.new("RGBA",SIZE,(0,0,0,0)); d=ImageDraw.Draw(glow)
    cx,cy=170,885
    for radius,alpha in ((150,12),(105,26),(68,50),(34,90)): d.ellipse((cx-radius,cy-radius,cx+radius,cy+radius),fill=(218,87,255,int(alpha*p)))
    # Subtle environmental lightning accents; never paint over the character silhouette.
    for points in [((40,80),(82,210),(54,335)),((860,65),(803,170),(842,300)),((920,1060),(970,1200),(948,1340))]:
        d.line(points,fill=(232,169,255,int(34*p)),width=8)
    glow=glow.filter(ImageFilter.GaussianBlur(25)); layer=Image.alpha_composite(layer,glow)
    path=SPRITES/f"energy_pulse_{i}.webp"; layer.save(path,"WEBP",lossless=True,method=6); return path

def main():
    SPRITES.mkdir(parents=True,exist_ok=True); QA.mkdir(parents=True,exist_ok=True)
    spec=get_json(SCENES_BUCKET,f"{SID}.json")
    if spec.get("published") is not False: raise RuntimeError("Scene must remain hidden")
    with Image.open(MASTER) as src:
        rgb=src.convert("RGB"); static=enc(rgb,88); preview=rgb.resize((540,1170),Image.Resampling.LANCZOS)
        for q in (24,18,14,10):
            prev=enc(preview,q)
            if len(prev)<50000: break
        if len(prev)>=50000: raise RuntimeError("Preview exceeds 50 KB")
    for key in (SID,STATIC_ID): put(IMG_BUCKET,f"{key}.webp",static); put(IMG_BUCKET,f"{key}_preview.webp",prev)
    layers=[x for x in spec.get("image_layers",[]) if not x.get("key","").startswith("energy_pulse_")]
    rev=max(int(x.get("revision",1)) for x in layers)+1
    for x in layers: x["revision"]=rev
    for i,p in enumerate(PHASES):
        path=frame(i,p); remote=f"{SID}_energy_pulse_{i}.webp"; put(IMG_BUCKET,remote,path.read_bytes())
        layers.append({"key":f"energy_pulse_{i}","url":url(remote),"z":2,"parallax_factor":0.018,"scroll_factor":0.0,"scale":1.26,"offset_x_px":0,"offset_y_px":0,"initial_alpha":1.0 if i==0 else 0.0,"revision":rev})
    spec["image_layers"]=layers; spec["cycles"]=[{"name":"violet_energy","duration_s":3.2,"frames":[{"layer_key":f"energy_pulse_{i}","from_s":i*.8,"to_s":(i+1)*.8} for i in range(4)]}]; spec["published"]=False
    put_json(SCENES_BUCKET,f"{SID}.json",spec)
    catalog=get_json(IMG_BUCKET,"catalog_index.json"); matches=[x for x in catalog.get("items",[]) if x.get("id")==SID]
    if len(matches)!=1 or matches[0].get("published") is not False: raise RuntimeError("Hidden catalog entry missing")
    catalog["version"]=int(catalog.get("version",0))+1; put_json(IMG_BUCKET,"catalog_index.json",catalog)
    from apply_migration import connect
    conn=connect(); cur=conn.cursor(); cur.execute("UPDATE wallpapers SET image_size=%s,preview_size=%s WHERE id=%s AND published=false",(len(static),len(prev),SID))
    if cur.rowcount!=1: raise RuntimeError("Hidden canvas row missing")
    cur.execute("SELECT COALESCE(MAX(sort_order),0)+1 FROM wallpapers"); order=cur.fetchone()[0]
    cur.execute("""INSERT INTO wallpapers (id,name,description,type,category,tags,image_path,preview_path,image_size,preview_size,glow_color,badge,sort_order,featured,trending_score,published,daily_eligible,author_name,media_width,media_height)
      VALUES (%s,%s,%s,'static'::wallpaper_type,'ANIME'::wallpaper_category,%s,%s,%s,%s,%s,'#C35CFF','NEW'::wallpaper_badge,%s,false,0,false,false,'Pixora Studio',1080,2340)
      ON CONFLICT(id) DO UPDATE SET name=EXCLUDED.name,description=EXCLUDED.description,tags=EXCLUDED.tags,image_path=EXCLUDED.image_path,preview_path=EXCLUDED.preview_path,image_size=EXCLUDED.image_size,preview_size=EXCLUDED.preview_size,published=false,updated_at=now()""",
      (STATIC_ID,"Majin Buu: tormenta violeta","Majin Buu domina un crater alienigena bajo una tormenta de energia.",["majin buu","dragon ball","anime","fan art","villano","energia"],f"{STATIC_ID}.webp",f"{STATIC_ID}_preview.webp",len(static),len(prev),order))
    conn.commit(); cur.close(); conn.close(); remote=get_json(SCENES_BUCKET,f"{SID}.json")
    (ROOT/"SCENE_SPEC_QA.json").write_text(json.dumps(remote,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    receipt={"scene_id":SID,"updated_at":datetime.now(timezone.utc).isoformat(),"published":False,"catalog_version":catalog["version"],"revision":rev,"energy_frames":4,"cycle_seconds":3.2,"static_id":STATIC_ID,"preview_bytes":len(prev),"hidden_verified":True}
    (QA/"ENERGY_TUNE_RECEIPT.json").write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n",encoding="utf-8"); print(json.dumps(receipt,ensure_ascii=False,indent=2))

if __name__=="__main__": main()
