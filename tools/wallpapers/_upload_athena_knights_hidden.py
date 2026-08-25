"""Upload Athena and Bronze Saints hidden for Huawei QA."""
import json
from _upload_depth_batch_20260824_hidden import upload_hidden
from _fcm_push import send_catalog_invalidate
CONFIG={"scene_id":"athena_caballeros_santuario_depth","folder":"athena_caballeros_santuario_20260825","rgb":"production/athena_caballeros_santuario_1080x2340.png","depth":"production/athena_caballeros_santuario_depth_1080x2340.png","depth_strength":0.25,"parallax":0.036,"scale":1.26,"title":{"es":"Athena y los Caballeros del Santuario","en":"Athena and the Knights of Sanctuary"},"name":"Athena y los Caballeros del Santuario","plain":"Athena y los cinco Caballeros de Bronce protegen el Santuario al atardecer.","tags":["athena","saint seiya","caballeros del zodiaco","seiya","shiryu","hyoga","shun","ikki","anime","fan art","2.5d"],"category":"anime","glow":"#FFD66B","particles":[{"kind":"motes","params":{"count":10,"drift":0.008,"vy_min":-0.004,"vy_max":-0.001,"color":"#FFE29A","max_alpha":25}}]}
if __name__=="__main__":
 r=upload_hidden(CONFIG)
 if not send_catalog_invalidate("wallpapers"):raise RuntimeError("FCM failed")
 print(json.dumps(r,ensure_ascii=False,indent=2))
