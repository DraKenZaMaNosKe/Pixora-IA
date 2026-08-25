"""Upload the cosmic world-devourer scene hidden for Huawei QA."""
import json
from _upload_depth_batch_20260824_hidden import upload_hidden
from _fcm_push import send_catalog_invalidate

CONFIG={"scene_id":"galactus_devorador_mundos_depth","folder":"galactus_devorador_mundos_20260824",
"rgb":"production/galactus_devorador_mundos_1080x2340.png","depth":"production/galactus_devorador_mundos_depth_1080x2340.png",
"depth_strength":0.30,"parallax":0.042,"scale":1.26,"title":{"es":"Galactus: devorador de mundos","en":"Galactus: Devourer of Worlds"},
"name":"Galactus: devorador de mundos","plain":"Una entidad cosmica emerge sobre un planeta mientras su mano atraviesa el primer plano.",
"tags":["galactus","marvel","comic","fan art","cosmico","planeta","2.5d","depth map","parallax"],"category":"gaming","glow":"#B86CFF",
"particles":[{"kind":"motes","params":{"count":10,"drift":0.008,"vy_min":-0.004,"vy_max":-0.001,"color":"#D9B0FF","max_alpha":26}}]}

if __name__=="__main__":
    receipt=upload_hidden(CONFIG)
    if not send_catalog_invalidate("wallpapers"): raise RuntimeError("FCM invalidation failed")
    print(json.dumps(receipt,ensure_ascii=False,indent=2))
