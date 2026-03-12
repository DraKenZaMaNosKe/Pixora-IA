"""
Remove Gemini watermark (4-point star) from bottom-right corner of images.
Crops the bottom ~15px and right ~15px to completely remove the watermark area.

Usage: python remove_gemini_watermark.py [input_dir] [output_dir]
"""

import sys
import os
import glob
from PIL import Image


def remove_watermark(img):
    """Remove the Gemini star by cropping the bottom-right edge."""
    w, h = img.size
    # The star sits in the very bottom-right corner
    # Crop 60px from right and 60px from bottom to completely remove it
    crop_right = 60
    crop_bottom = 60
    return img.crop((0, 0, w - crop_right, h - crop_bottom))


def process_images(input_dir, output_dir):
    """Process all Gemini images in directory."""
    os.makedirs(output_dir, exist_ok=True)

    patterns = [
        os.path.join(input_dir, 'Gemini_Generated_Image_*.png'),
        os.path.join(input_dir, 'Gemini_Generated_Image_*.jpg'),
    ]

    files = []
    for pattern in patterns:
        files.extend(glob.glob(pattern))

    if not files:
        print(f"No Gemini images found in {input_dir}")
        return

    print(f"Found {len(files)} images to process")

    for i, filepath in enumerate(sorted(files)):
        filename = os.path.basename(filepath)
        new_name = f"icon_room_{i+1:02d}.png"
        output_path = os.path.join(output_dir, new_name)

        print(f"  [{i+1}/{len(files)}] {filename} -> {new_name}")

        img = Image.open(filepath)
        cleaned = remove_watermark(img)
        cleaned.save(output_path, quality=95)

    print(f"\nDone! {len(files)} images saved to {output_dir}")


if __name__ == '__main__':
    input_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/Downloads')
    output_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.dirname(__file__)), 'assets', 'icon_rooms')

    process_images(input_dir, output_dir)
