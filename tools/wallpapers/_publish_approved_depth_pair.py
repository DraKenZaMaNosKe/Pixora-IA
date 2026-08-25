"""Publish a Huawei-approved hidden static + Depth 2.5D pair with rollback."""
from __future__ import annotations

import argparse
import json
import sys
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE), str(HERE.parent)]
from apply_migration import connect
from _fcm_push import send_catalog_invalidate
from _upload_scene_generic import IMG_BUCKET, SCENES_BUCKET, get_json, put_json


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path); parser.add_argument("sid"); parser.add_argument("static_id")
    parser.add_argument("--layers", type=int, required=True); parser.add_argument("--revision", type=int, required=True)
    parser.add_argument("--qa-prefix", required=True); parser.add_argument("--qa-count", type=int, default=3)
    args = parser.parse_args(); root = args.root.resolve()
    approved = json.loads((root/"SCENE_SPEC_QA.json").read_text(encoding="utf-8"))
    remote = get_json(SCENES_BUCKET, f"{args.sid}.json")
    if remote != approved or remote.get("published") is not False or remote.get("id") != args.sid:
        raise RuntimeError("Remote spec differs from hidden Huawei-approved spec")
    layers = remote.get("image_layers", [])
    if len(layers) != args.layers or any(int(layer.get("revision", 0)) != args.revision for layer in layers):
        raise RuntimeError("Approved layer inventory or revision changed")
    qa_files = [root/f"qa/{args.qa_prefix}{i}.png" for i in range(1, args.qa_count+1)]
    if any(not path.is_file() or path.stat().st_size < 100_000 for path in qa_files):
        raise RuntimeError("Missing Huawei QA evidence")
    catalog = get_json(IMG_BUCKET, "catalog_index.json")
    matches = [item for item in catalog.get("items", []) if item.get("id") == args.sid]
    if len(matches) != 1 or matches[0].get("published") is not False: raise RuntimeError("Canvas catalog entry is not hidden")
    spec_before, catalog_before = deepcopy(remote), deepcopy(catalog); next_version = int(catalog.get("version", 0))+1
    outputs = [root/"SCENE_SPEC_PRODUCTION.json", root/"PRODUCTION_RECEIPT.json"]
    output_before = {path: path.read_bytes() if path.exists() else None for path in outputs}
    conn = connect(); cur = conn.cursor()
    cur.execute("SELECT id,published FROM wallpapers WHERE id IN (%s,%s) ORDER BY id", (args.sid,args.static_id))
    if cur.fetchall() != [(args.sid,False),(args.static_id,False)]: cur.close(); conn.close(); raise RuntimeError("Postgres variants are not both hidden")
    try:
        remote["published"] = True; matches[0]["published"] = True; catalog["version"] = next_version
        put_json(SCENES_BUCKET, f"{args.sid}.json", remote); put_json(IMG_BUCKET, "catalog_index.json", catalog)
        cur.execute("UPDATE wallpapers SET published=true WHERE id IN (%s,%s) RETURNING id,published", (args.sid,args.static_id))
        if sorted(cur.fetchall()) != [(args.sid,True),(args.static_id,True)]: raise RuntimeError("Postgres publication failed")
        conn.commit()
        if not send_catalog_invalidate("wallpapers"): raise RuntimeError("FCM invalidation was not confirmed")
        verified = get_json(SCENES_BUCKET, f"{args.sid}.json"); verified_catalog = get_json(IMG_BUCKET,"catalog_index.json")
        cur.execute("SELECT id,published FROM wallpapers WHERE id IN (%s,%s) ORDER BY id", (args.sid,args.static_id)); db_rows=cur.fetchall()
        expected=deepcopy(approved); expected["published"]=True
        cat_matches=[item for item in verified_catalog.get("items",[]) if item.get("id")==args.sid]
        if verified != expected or len(cat_matches)!=1 or cat_matches[0].get("published") is not True or db_rows != [(args.sid,True),(args.static_id,True)]:
            raise RuntimeError("Remote publication verification failed")
        receipt={"scene_id":args.sid,"static_id":args.static_id,"published_at":datetime.now(timezone.utc).isoformat(),
                 "catalog_version":next_version,"triple_published":True,"static_published":True,"revision":args.revision,
                 "layer_count":args.layers,"qa_devices":["HUAWEI VNS-L53"],
                 "qa_captures":[f"qa/{path.name}" for path in qa_files],"fcm_catalog_invalidate":True}
        outputs[0].write_text(json.dumps(verified,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        outputs[1].write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        print(json.dumps(receipt,ensure_ascii=False,indent=2))
    except Exception as original:
        errors=[]
        try: conn.rollback()
        except Exception as exc: errors.append(f"db rollback: {exc}")
        try: put_json(SCENES_BUCKET,f"{args.sid}.json",spec_before)
        except Exception as exc: errors.append(f"spec rollback: {exc}")
        try: put_json(IMG_BUCKET,"catalog_index.json",catalog_before)
        except Exception as exc: errors.append(f"catalog rollback: {exc}")
        try: cur.execute("UPDATE wallpapers SET published=false WHERE id IN (%s,%s)",(args.sid,args.static_id)); conn.commit()
        except Exception as exc: errors.append(f"db restore: {exc}")
        for path,previous in output_before.items():
            try: path.unlink(missing_ok=True) if previous is None else path.write_bytes(previous)
            except Exception as exc: errors.append(f"output restore {path.name}: {exc}")
        try: send_catalog_invalidate("wallpapers")
        except Exception as exc: errors.append(f"FCM compensatory: {exc}")
        if errors: raise RuntimeError("Incomplete rollback: "+" | ".join(errors)) from original
        raise
    finally: cur.close(); conn.close()


if __name__ == "__main__": main()
