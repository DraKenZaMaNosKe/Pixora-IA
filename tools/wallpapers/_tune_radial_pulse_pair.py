"""Reusable hidden-scene tuner: static pair plus four-frame radial light cycle."""
import argparse,io,json,sys
from datetime import datetime,timezone
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter
HERE=Path(__file__).resolve().parent;sys.path[:0]=[str(HERE),str(HERE.parent)]
from _upload_scene_generic import IMG_BUCKET,PROJECT,SCENES_BUCKET,get_json,put,put_json

def enc(im,q):o=io.BytesIO();im.save(o,"WEBP",quality=q,method=6);return o.getvalue()
def main():
 p=argparse.ArgumentParser();p.add_argument("root",type=Path);p.add_argument("sid");p.add_argument("static_id");p.add_argument("master",type=Path);p.add_argument("--name",required=True);p.add_argument("--description",required=True);p.add_argument("--tags",required=True);p.add_argument("--category",choices=["ANIME","GAMING"],default="ANIME");p.add_argument("--color",required=True);p.add_argument("--point",action="append",required=True);p.add_argument("--cycle",type=float,default=4.0);p.add_argument("--prefix",default="living_light");p.add_argument("--scale",type=float,default=1.26);a=p.parse_args();root=a.root.resolve();spr=root/"sprites";qa=root/"qa";spr.mkdir(parents=True,exist_ok=True);qa.mkdir(parents=True,exist_ok=True);size=(1080,2340);rgbc=tuple(int(a.color[i:i+2],16) for i in (1,3,5));points=[tuple(map(int,x.split(","))) for x in a.point]
 spec=get_json(SCENES_BUCKET,f"{a.sid}.json")
 if spec.get("published") is not False:raise RuntimeError("Scene must remain hidden")
 with Image.open(a.master) as src:
  rgb=src.convert("RGB")
  if rgb.size!=size:raise RuntimeError(f"Unexpected master size {rgb.size}")
  static=enc(rgb,88);pr=rgb.resize((540,1170),Image.Resampling.LANCZOS)
  for q in (22,16,12,9):
   prev=enc(pr,q)
   if len(prev)<50000:break
  if len(prev)>=50000:raise RuntimeError("Preview over 50 KB")
 for key in (a.sid,a.static_id):put(IMG_BUCKET,f"{key}.webp",static);put(IMG_BUCKET,f"{key}_preview.webp",prev)
 layers=[x for x in spec.get("image_layers",[]) if not x.get("key","").startswith(a.prefix+"_")];rev=max(int(x.get("revision",1)) for x in layers)+1
 for x in layers:
  x["revision"]=rev
  if x.get("key")=="background":x["scale"]=a.scale
 phases=(.30,.60,1.0,.60)
 for i,phase in enumerate(phases):
  im=Image.new("RGBA",size,(0,0,0,0));g=Image.new("RGBA",size,(0,0,0,0));d=ImageDraw.Draw(g)
  for n,(cx,cy) in enumerate(points):
   local=phase if (n+i)%2==0 else max(.25,1.15-phase*.45)
   for radius,alpha in ((95,10),(55,24),(24,65)):d.ellipse((cx-radius,cy-radius,cx+radius,cy+radius),fill=(*rgbc,int(alpha*local)))
  g=g.filter(ImageFilter.GaussianBlur(18));im=Image.alpha_composite(im,g);path=spr/f"{a.prefix}_{i}.webp";im.save(path,"WEBP",lossless=True,method=6);remote=f"{a.sid}_{a.prefix}_{i}.webp";put(IMG_BUCKET,remote,path.read_bytes());layers.append({"key":f"{a.prefix}_{i}","url":f"{PROJECT}/storage/v1/object/public/{IMG_BUCKET}/{remote}","z":2,"parallax_factor":.012,"scroll_factor":0.0,"scale":a.scale,"offset_x_px":0,"offset_y_px":0,"initial_alpha":1.0 if i==0 else 0.0,"revision":rev})
 spec["image_layers"]=layers;step=a.cycle/4;spec["cycles"]=[{"name":a.prefix,"duration_s":a.cycle,"frames":[{"layer_key":f"{a.prefix}_{i}","from_s":i*step,"to_s":(i+1)*step} for i in range(4)]}];spec["published"]=False;put_json(SCENES_BUCKET,f"{a.sid}.json",spec)
 cat=get_json(IMG_BUCKET,"catalog_index.json");m=[x for x in cat.get("items",[]) if x.get("id")==a.sid]
 if len(m)!=1 or m[0].get("published") is not False:raise RuntimeError("Hidden catalog entry missing")
 cat["version"]=int(cat.get("version",0))+1;put_json(IMG_BUCKET,"catalog_index.json",cat)
 from apply_migration import connect
 conn=connect();cur=conn.cursor();cur.execute("UPDATE wallpapers SET image_size=%s,preview_size=%s WHERE id=%s AND published=false",(len(static),len(prev),a.sid))
 if cur.rowcount!=1:raise RuntimeError("Hidden canvas row missing")
 cur.execute("SELECT COALESCE(MAX(sort_order),0)+1 FROM wallpapers");order=cur.fetchone()[0]
 cur.execute(f"""INSERT INTO wallpapers(id,name,description,type,category,tags,image_path,preview_path,image_size,preview_size,glow_color,badge,sort_order,featured,trending_score,published,daily_eligible,author_name,media_width,media_height) VALUES(%s,%s,%s,'static'::wallpaper_type,'{a.category}'::wallpaper_category,%s,%s,%s,%s,%s,%s,'NEW'::wallpaper_badge,%s,false,0,false,false,'Pixora Studio',1080,2340) ON CONFLICT(id) DO UPDATE SET name=EXCLUDED.name,description=EXCLUDED.description,tags=EXCLUDED.tags,image_path=EXCLUDED.image_path,preview_path=EXCLUDED.preview_path,image_size=EXCLUDED.image_size,preview_size=EXCLUDED.preview_size,glow_color=EXCLUDED.glow_color,published=false,updated_at=now()""",(a.static_id,a.name,a.description,[x.strip() for x in a.tags.split(",")],f"{a.static_id}.webp",f"{a.static_id}_preview.webp",len(static),len(prev),a.color,order));conn.commit();cur.close();conn.close()
 remote=get_json(SCENES_BUCKET,f"{a.sid}.json");(root/"SCENE_SPEC_QA.json").write_text(json.dumps(remote,ensure_ascii=False,indent=2)+"\n",encoding="utf-8");receipt={"scene_id":a.sid,"updated_at":datetime.now(timezone.utc).isoformat(),"published":False,"catalog_version":cat["version"],"revision":rev,"frames":4,"cycle_seconds":a.cycle,"static_id":a.static_id,"preview_bytes":len(prev),"hidden_verified":True};(qa/"LIGHT_TUNE_RECEIPT.json").write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n",encoding="utf-8");print(json.dumps(receipt,ensure_ascii=False,indent=2))
if __name__=="__main__":main()
