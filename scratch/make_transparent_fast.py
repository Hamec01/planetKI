import os
import glob
from PIL import Image, ImageDraw

def make_transparent(img_path):
    img = Image.open(img_path).convert("RGBA")
    w, h = img.size
    
    seed_points = [
        (0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
        (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2),
        (w // 4, 0), (3 * w // 4, 0), (0, h // 4), (0, 3 * h // 4),
        (w - 1, h // 4), (w - 1, 3 * h // 4)
    ]
    
    for pt in seed_points:
        r, g, b, a = img.getpixel(pt)
        if r < 35 and g < 35 and b < 35:
            ImageDraw.floodfill(img, pt, (0, 0, 0, 0), thresh=32)
            
    img.save(img_path, "PNG")

if __name__ == "__main__":
    folder = r"E:\Planetki\Assets\buildings\Dom_roda"
    pngs = glob.glob(os.path.join(folder, "*.png"))
    for i, p in enumerate(pngs):
        make_transparent(p)
        print(f"[{i+1}/{len(pngs)}] Done file: {i}")
    print("ALL SPRITES TRANSPARENT OK!")
