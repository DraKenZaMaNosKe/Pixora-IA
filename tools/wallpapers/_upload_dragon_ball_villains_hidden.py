"""Upload Dragon Ball villains gallery hidden for Huawei QA."""
import json
from _upload_depth_batch_20260824_hidden import upload_hidden
from _fcm_push import send_catalog_invalidate
CONFIG={"scene_id":"dragon_ball_galeria_villanos_depth","folder":"dragon_ball_galeria_villanos_20260825","rgb":"production/dragon_ball_galeria_villanos_1080x2340.png","depth":"production/dragon_ball_galeria_villanos_depth_1080x2340.png","depth_strength":0.26,"parallax":0.038,"scale":1.26,"title":{"es":"Dragon Ball: galería de villanos","en":"Dragon Ball: Villains Gallery"},"name":"Dragon Ball: galería de villanos","plain":"Las mayores amenazas de distintas eras convergen en un mural cosmico fracturado.","tags":["dragon ball","villanos","freezer","cell","majin buu","goku black","anime","fan art","2.5d","depth map"],"category":"anime","glow":"#FF375F","particles":[{"kind":"embers","params":{"count":12,"speed":0.13,"color":"#FF375F","min_size":0.7,"max_size":1.8}}]}
if __name__=="__main__":
 r=upload_hidden(CONFIG)
 if not send_catalog_invalidate("wallpapers"):raise RuntimeError("FCM failed")
 print(json.dumps(r,ensure_ascii=False,indent=2))
