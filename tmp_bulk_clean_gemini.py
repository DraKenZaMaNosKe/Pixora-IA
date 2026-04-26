"""Scan all wallpapers in dynamic_catalog.json, detect the Gemini sparkle
   in the bottom-right corner, inpaint + re-upload the ones that have it.

Strategy:
  1. Fetch dynamic_catalog.json from Supabase
  2. For each wallpaper, download the .webp from wallpaper-images bucket
  3. Detect sparkle: bottom-right region, threshold + contour with shape
     constraints (area in expected range, aspect ratio near 1)
  4. If found: inpaint via OpenCV TELEA, re-upload .webp
  5. Same for the preview file

Runs sequentially (Supabase rate limits + simplicity). Logs every step.
"""
import io
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np
import requests
from PIL import Image

SUPABASE_URL = "https://vzuwvsmlyigjtsearxym.supabase.co"
SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ6dXd2c21seWlnanRzZWFyeHltIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1ODY0ODcwOSwiZXhwIjoyMDc0MjI0NzA5fQ.xDs_HCkdqcEVJktzTdjGIXnG-V--j86jbkrUA4SjAOs"
H = {"Authorization": f"Bearer {SERVICE_KEY}", "apikey": SERVICE_KEY}
BUCKET = "wallpaper-images"


def fetch_bytes(remote: str) -> bytes | None:
    url = f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{remote}"
    r = requests.get(url, timeout=30)
    return r.content if r.status_code == 200 else None


def upload_bytes(remote: str, body: bytes, ctype: str) -> bool:
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{remote}"
    h = {**H, "Content-Type": ctype, "x-upsert": "true"}
    r = requests.put(url, headers=h, data=body, timeout=120)
    return r.status_code in (200, 201)


def detect_sparkle_mask(img):
    """Return a binary mask of the Gemini sparkle, or None if not found.

    Tuned for the AI sparkle: a bright (~130-180 grayscale) ~diamond/star
    shape in the bottom-right corner, area roughly 1500-6000 px on a
    1080x2340 image (smaller for previews/thumbs).
    """
    h, w = img.shape[:2]
    # Tight bottom-right corner search (the sparkle always lives here)
    rx0 = int(w * 0.78)
    ry0 = int(h * 0.88)
    region = img[ry0:h, rx0:w]
    gray = cv2.cvtColor(region, cv2.COLOR_BGR2GRAY)

    # Adaptive thresholds — try a few until something plausible appears
    best = None
    # Scale area window with image size
    img_area = h * w
    # baseline 1080x2340 = 2.5M px → expect 1500-6000 area
    area_min = max(120, int(img_area * 1500 / (1080 * 2340)))
    area_max = max(800, int(img_area * 6000 / (1080 * 2340)))

    for thresh in [110, 125, 140, 160]:
        _, m = cv2.threshold(gray, thresh, 255, cv2.THRESH_BINARY)
        m = cv2.morphologyEx(m, cv2.MORPH_CLOSE,
            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)))
        contours, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        for c in contours:
            area = cv2.contourArea(c)
            if not (area_min <= area <= area_max):
                continue
            x, y, cw, ch = cv2.boundingRect(c)
            aspect = max(cw, ch) / max(min(cw, ch), 1)
            if aspect > 2.5:
                continue
            # Score by compactness (sparkle has ~20-30% bbox fill, very
            # different from random bright blobs)
            fill = area / (cw * ch)
            if fill > 0.55:
                continue  # too solid, probably not a sparkle
            if best is None or area > best[0]:
                best = (area, c)

    if best is None:
        return None

    full_mask = np.zeros((h, w), dtype=np.uint8)
    c2 = best[1] + np.array([rx0, ry0])
    cv2.drawContours(full_mask, [c2], -1, 255, thickness=cv2.FILLED)
    full_mask = cv2.dilate(full_mask,
        cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)), iterations=2)
    return full_mask


def clean_image(webp_bytes: bytes):
    """Returns (cleaned_webp_bytes_or_None, mask_pixels) — None if no sparkle."""
    arr = np.frombuffer(webp_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        return None, 0
    mask = detect_sparkle_mask(img)
    if mask is None:
        return None, 0
    px = int(mask.sum() / 255)
    cleaned = cv2.inpaint(img, mask, inpaintRadius=8, flags=cv2.INPAINT_NS)
    # Re-encode as WebP via PIL for consistent quality
    rgb = cv2.cvtColor(cleaned, cv2.COLOR_BGR2RGB)
    pil = Image.fromarray(rgb)
    buf = io.BytesIO()
    pil.save(buf, "WEBP", quality=88, method=6)
    return buf.getvalue(), px


def main():
    print("Fetching dynamic_catalog.json...")
    r = requests.get(f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/dynamic_catalog.json", timeout=30)
    if r.status_code != 200:
        print(f"FAIL: HTTP {r.status_code}")
        sys.exit(1)
    catalog = r.json()
    items = catalog.get("wallpapers", [])
    print(f"  {len(items)} wallpapers in catalog")

    # Build de-duplicated list of files to process (full + preview)
    files = []  # list of (id, remote_filename, role)
    for it in items:
        wid = it.get("id", "?")
        if it.get("imageFile"):
            files.append((wid, it["imageFile"], "full"))
        if it.get("previewFile"):
            files.append((wid, it["previewFile"], "preview"))

    print(f"  {len(files)} files to scan")
    print()

    cleaned_count = 0
    not_found = 0
    failed = 0
    cleaned_ids = set()

    t0 = time.time()
    for i, (wid, fname, role) in enumerate(files, start=1):
        prefix = f"[{i}/{len(files)}] {wid} ({role})"
        try:
            data = fetch_bytes(fname)
            if data is None:
                print(f"  {prefix}: download failed")
                failed += 1
                continue
            cleaned, px = clean_image(data)
            if cleaned is None:
                # Sparkle not detected, skip
                if i % 20 == 0:
                    elapsed = time.time() - t0
                    print(f"  ...processed {i}, scanned-clean: {not_found+1}, "
                          f"sparkles found: {cleaned_count}, elapsed {elapsed:.0f}s")
                not_found += 1
                continue
            # Re-upload
            if upload_bytes(fname, cleaned, "image/webp"):
                cleaned_count += 1
                cleaned_ids.add(wid)
                print(f"  {prefix}: ✨ cleaned {px}px → re-uploaded {len(cleaned):,} B")
            else:
                failed += 1
                print(f"  {prefix}: cleaned but upload FAILED")
        except Exception as e:
            failed += 1
            print(f"  {prefix}: error {e}")

    elapsed = time.time() - t0
    print()
    print(f"=== DONE in {elapsed:.0f}s ===")
    print(f"  scanned:           {len(files)}")
    print(f"  sparkles cleaned:  {cleaned_count}")
    print(f"  no sparkle found:  {not_found}")
    print(f"  failed:            {failed}")
    print()
    if cleaned_ids:
        print(f"  cleaned wallpaper IDs ({len(cleaned_ids)}):")
        for wid in sorted(cleaned_ids):
            print(f"    {wid}")


if __name__ == "__main__":
    main()
