"""Upload the Majin Buu Depth 2.5D scene hidden for Huawei QA."""
import json
from _upload_depth_batch_20260824_hidden import upload_hidden
from _fcm_push import send_catalog_invalidate


CONFIG = {
    "scene_id": "majin_buu_tormenta_violeta_depth",
    "folder": "majin_buu_tormenta_violeta_20260824",
    "rgb": "production/majin_buu_tormenta_violeta_1080x2340.png",
    "depth": "production/majin_buu_tormenta_violeta_depth_1080x2340.png",
    "depth_strength": 0.34,
    "parallax": 0.045,
    "scale": 1.26,
    "title": {"es": "Majin Buu: tormenta violeta", "en": "Majin Buu: Violet Storm"},
    "name": "Majin Buu: tormenta violeta",
    "plain": "Majin Buu domina un crater alienigena mientras la energia violeta altera cada plano.",
    "tags": ["majin buu", "dragon ball", "anime", "fan art", "villano", "energia", "tormenta", "2.5d", "depth map", "parallax"],
    "category": "anime",
    "glow": "#C35CFF",
    "particles": [{"kind": "embers", "params": {"count": 10, "speed": 0.12, "color": "#D98CFF", "min_size": 0.7, "max_size": 1.8}}],
}


if __name__ == "__main__":
    receipt = upload_hidden(CONFIG)
    if not send_catalog_invalidate("wallpapers"):
        raise RuntimeError("Final FCM invalidation was not confirmed")
    print(json.dumps(receipt, ensure_ascii=False, indent=2))
