"""Prepara las capas de Afrodita: Jardín de la Espuma."""
from __future__ import annotations
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(r"G:/Mi unidad/pixoraIA_admin/ia_contenido_pipeline/wallpapers/1_por_editar/afrodita_jardin_espuma_20260820")
TARGET=(1080,2340); BG_OVERSCAN=(1200,2600)

def cover(image, size):
    src=image.convert("RGB"); scale=max(size[0]/src.width,size[1]/src.height)
    resized=src.resize((round(src.width*scale),round(src.height*scale)),Image.Resampling.LANCZOS)
    left=(resized.width-size[0])//2; top=(resized.height-size[1])//2
    return resized.crop((left,top,left+size[0],top+size[1]))

def resize_rgba(image,size):
    rgba=np.asarray(image.convert("RGBA"),dtype=np.float32); alpha=rgba[:,:,3:4]/255.0; premul=rgba[:,:,:3]*alpha
    channels=[np.asarray(Image.fromarray(premul[:,:,i].astype("uint8"),"L").resize(size,Image.Resampling.LANCZOS),dtype=np.float32) for i in range(3)]
    ao=np.asarray(Image.fromarray(rgba[:,:,3].astype("uint8"),"L").resize(size,Image.Resampling.LANCZOS),dtype=np.float32)
    rgb=np.clip(np.stack(channels,axis=2)/np.maximum(ao[:,:,None]/255.0,1/255),0,255)
    out=np.dstack([rgb,ao]).astype("uint8"); out[ao==0,:3]=0
    return Image.fromarray(out,"RGBA")

def main():
    bg=cover(Image.open(ROOT/"source/aphrodite_background_original.png"),BG_OVERSCAN); bg.save(ROOT/"parallax/layers/background.png")
    cut=resize_rgba(Image.open(ROOT/"source/aphrodite_character_alpha.png"),(900,1350))
    char=Image.new("RGBA",TARGET,(0,0,0,0)); char.alpha_composite(cut,(90,760)); char.save(ROOT/"parallax/layers/aphrodite_and_dove.png")
    mask=Image.new("L",TARGET,0); d=ImageDraw.Draw(mask)
    d.ellipse((205,1040,355,1190),fill=145); d.ellipse((480,1160,610,1290),fill=110); d.ellipse((740,830,970,1070),fill=80)
    glow=mask.filter(ImageFilter.GaussianBlur(12)); aura=Image.new("RGBA",TARGET,(255,204,225,0)); aura.putalpha(glow.point(lambda v:min(88,v)))
    aura.save(ROOT/"parallax/layers/pearl_aura.png")
    flat=Image.alpha_composite(cover(bg,TARGET).convert("RGBA"),aura); flat=Image.alpha_composite(flat,char).convert("RGB")
    flat.save(ROOT/"static/afrodita_jardin_espuma_wallpaper.png",quality=96); flat.save(ROOT/"parallax/preview/afrodita_jardin_espuma_preview.png",quality=94)
    (ROOT/"PREPARATION_REPORT.json").write_text(json.dumps({"target":list(TARGET),"background_overscan":list(BG_OVERSCAN),"character_size":[900,1350],"character_xy":[90,760],"layers":["background","pearl_aura","aphrodite_and_dove"],"source_preserved":True},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

if __name__=="__main__": main()
