"""Upload Violeta Tinta hidden for Huawei QA."""
import json
from _upload_depth_batch_20260824_hidden import upload_hidden
from _fcm_push import send_catalog_invalidate
CONFIG={"scene_id":"violeta_tinta_lluvia_depth","folder":"violeta_tinta_lluvia_20260825","rgb":"production/violeta_tinta_lluvia_1080x2340.png","depth":"production/violeta_tinta_lluvia_depth_1080x2340.png","depth_strength":0.28,"parallax":0.040,"scale":1.26,"title":{"es":"Violeta Tinta bajo la lluvia","en":"Violeta Ink in the Rain"},"name":"Violeta Tinta bajo la lluvia","plain":"Una guardiana de recuerdos escucha las palabras escondidas en la lluvia de Noctilucia.","tags":["violeta tinta","original","gotico","lluvia","luna","chica","2.5d","depth map","parallax"],"category":"anime","glow":"#A970FF","particles":[{"kind":"motes","params":{"count":12,"drift":0.009,"vy_min":-0.006,"vy_max":-0.001,"color":"#B984FF","max_alpha":30}}]}
if __name__=="__main__":
 r=upload_hidden(CONFIG)
 if not send_catalog_invalidate("wallpapers"): raise RuntimeError("FCM failed")
 print(json.dumps(r,ensure_ascii=False,indent=2))
