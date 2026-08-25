"""Add cosmic core and planet-rim light to hidden Galactus scene."""
import io,json,sys
from datetime import datetime,timezone
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter
HERE=Path(__file__).resolve().parent; sys.path[:0]=[str(HERE),str(HERE.parent)]
from _upload_scene_generic import IMG_BUCKET,PROJECT,SCENES_BUCKET,get_json,put,put_json
SID="galactus_devorador_mundos_depth"; STATIC_ID="galactus_devorador_mundos_static"
ROOT=Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/galactus_devorador_mundos_20260824"); MASTER=ROOT/"production/galactus_devorador_mundos_1080x2340.png"; SPRITES=ROOT/"sprites"; QA=ROOT/"qa"; SIZE=(1080,2340); PHASES=(.32,.58,1,.58)
def url(n): return f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{n}"
def enc(im,q): o=io.BytesIO(); im.save(o,"WEBP",quality=q,method=6); return o.getvalue()
def frame(i,p):
    im=Image.new("RGBA",SIZE,(0,0,0,0)); g=Image.new("RGBA",SIZE,(0,0,0,0)); d=ImageDraw.Draw(g)
    for cx,cy,color in ((700,1110,(255,151,84)),(555,790,(255,186,80))):
        for r,a in ((105,12),(65,28),(32,70)): d.ellipse((cx-r,cy-r,cx+r,cy+r),fill=(*color,int(a*p)))
    d.ellipse((-170,2030,1250,2490),outline=(123,210,255,int(78*p)),width=18)
    g=g.filter(ImageFilter.GaussianBlur(22)); im=Image.alpha_composite(im,g); path=SPRITES/f"cosmic_pulse_{i}.webp"; im.save(path,"WEBP",lossless=True,method=6); return path
def main():
    SPRITES.mkdir(parents=True,exist_ok=True); QA.mkdir(parents=True,exist_ok=True); spec=get_json(SCENES_BUCKET,f"{SID}.json")
    if spec.get("published") is not False: raise RuntimeError("Scene must remain hidden")
    with Image.open(MASTER) as s:
        rgb=s.convert("RGB"); static=enc(rgb,88); pr=rgb.resize((540,1170),Image.Resampling.LANCZOS)
        for q in (22,16,12,9):
            prev=enc(pr,q)
            if len(prev)<50000: break
        if len(prev)>=50000: raise RuntimeError("Preview too large")
    for key in (SID,STATIC_ID): put(IMG_BUCKET,f"{key}.webp",static); put(IMG_BUCKET,f"{key}_preview.webp",prev)
    layers=[x for x in spec.get("image_layers",[]) if not x.get("key","").startswith("cosmic_pulse_")]; rev=max(int(x.get("revision",1)) for x in layers)+1
    for x in layers:
        if x.get("key")=="background": x["scale"]=1.26; x["parallax_factor"]=0.042
    for x in layers:x["revision"]=rev
    for i,p in enumerate(PHASES):
        path=frame(i,p); remote=f"{SID}_cosmic_pulse_{i}.webp"; put(IMG_BUCKET,remote,path.read_bytes()); layers.append({"key":f"cosmic_pulse_{i}","url":url(remote),"z":2,"parallax_factor":.014,"scroll_factor":0.0,"scale":1.26,"offset_x_px":0,"offset_y_px":0,"initial_alpha":1.0 if i==0 else 0.0,"revision":rev})
    spec["image_layers"]=layers; spec["cycles"]=[{"name":"cosmic_core","duration_s":4.0,"frames":[{"layer_key":f"cosmic_pulse_{i}","from_s":i,"to_s":i+1} for i in range(4)]}]; spec["published"]=False; put_json(SCENES_BUCKET,f"{SID}.json",spec)
    cat=get_json(IMG_BUCKET,"catalog_index.json"); m=[x for x in cat.get("items",[]) if x.get("id")==SID]
    if len(m)!=1 or m[0].get("published") is not False: raise RuntimeError("Hidden catalog entry missing")
    cat["version"]=int(cat.get("version",0))+1; put_json(IMG_BUCKET,"catalog_index.json",cat)
    from apply_migration import connect
    conn=connect();cur=conn.cursor();cur.execute("UPDATE wallpapers SET image_size=%s,preview_size=%s WHERE id=%s AND published=false",(len(static),len(prev),SID));
    if cur.rowcount!=1: raise RuntimeError("Hidden canvas row missing")
    cur.execute("SELECT COALESCE(MAX(sort_order),0)+1 FROM wallpapers");order=cur.fetchone()[0]
    cur.execute("""INSERT INTO wallpapers(id,name,description,type,category,tags,image_path,preview_path,image_size,preview_size,glow_color,badge,sort_order,featured,trending_score,published,daily_eligible,author_name,media_width,media_height) VALUES(%s,%s,%s,'static'::wallpaper_type,'GAMING'::wallpaper_category,%s,%s,%s,%s,%s,'#B86CFF','NEW'::wallpaper_badge,%s,false,0,false,false,'Pixora Studio',1080,2340) ON CONFLICT(id) DO UPDATE SET name=EXCLUDED.name,description=EXCLUDED.description,tags=EXCLUDED.tags,image_path=EXCLUDED.image_path,preview_path=EXCLUDED.preview_path,image_size=EXCLUDED.image_size,preview_size=EXCLUDED.preview_size,published=false,updated_at=now()""",(STATIC_ID,"Galactus: devorador de mundos","Una entidad cosmica emerge sobre el horizonte de un planeta.",["galactus","marvel","comic","fan art","cosmico","planeta"],f"{STATIC_ID}.webp",f"{STATIC_ID}_preview.webp",len(static),len(prev),order));conn.commit();cur.close();conn.close()
    remote=get_json(SCENES_BUCKET,f"{SID}.json");(ROOT/"SCENE_SPEC_QA.json").write_text(json.dumps(remote,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    receipt={"scene_id":SID,"updated_at":datetime.now(timezone.utc).isoformat(),"published":False,"catalog_version":cat["version"],"revision":rev,"cosmic_frames":4,"cycle_seconds":4.0,"static_id":STATIC_ID,"preview_bytes":len(prev),"hidden_verified":True};(QA/"COSMIC_TUNE_RECEIPT.json").write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n",encoding="utf-8");print(json.dumps(receipt,ensure_ascii=False,indent=2))
if __name__=="__main__":main()
