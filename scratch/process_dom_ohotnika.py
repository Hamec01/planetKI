import os
import glob
from PIL import Image
from collections import deque

MAPPING = {
    "1": "hunter_lodge.png",
    "2": "destr_hunter_lodge.png",
    "3": "hunter_shelter.png",
    "4": "hunt_campfire.png",
    "5": "hunt_weapon_rack.png",
    "6": "hunt_fur_rack.png",
    "7": "hunt_butcher_table.png",
}

def make_background_transparent(src_path, dst_path):
    img = Image.open(src_path).convert("RGBA")
    w, h = img.size
    pixels = img.load()
    
    visited = set()
    queue = deque()
    
    def is_black(x, y, threshold=25):
        r, g, b, a = pixels[x, y]
        return r < threshold and g < threshold and b < threshold
    
    for x in range(w):
        if is_black(x, 0):
            queue.append((x, 0))
            visited.add((x, 0))
        if is_black(x, h - 1):
            queue.append((x, h - 1))
            visited.add((x, h - 1))
            
    for y in range(h):
        if is_black(0, y) and (0, y) not in visited:
            queue.append((0, y))
            visited.add((0, y))
        if is_black(w - 1, y) and (w - 1, y) not in visited:
            queue.append((w - 1, y))
            visited.add((w - 1, y))
            
    while queue:
        cx, cy = queue.popleft()
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < w and 0 <= ny < h:
                if (nx, ny) not in visited and is_black(nx, ny, 30):
                    visited.add((nx, ny))
                    queue.append((nx, ny))
                    
    for (x, y) in visited:
        r, g, b, a = pixels[x, y]
        pixels[x, y] = (r, g, b, 0)
        
    border_visited = set()
    for (x, y) in visited:
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)]:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in visited:
                border_visited.add((nx, ny))
                
    for (x, y) in border_visited:
        r, g, b, a = pixels[x, y]
        max_val = max(r, g, b)
        if max_val < 45:
            factor = max(0.0, min(1.0, (max_val - 10) / 35.0))
            pixels[x, y] = (r, g, b, int(a * factor))
            
    img.save(dst_path, "PNG")
    print(f"Saved: {os.path.basename(dst_path)}")

if __name__ == "__main__":
    folder = r"E:\Planetki\Assets\buildings\dom_ohotnika"
    files = os.listdir(folder)
    for f in sorted(files):
        if f.endswith(".png") and "(" in f and ")" in f:
            idx = f.split("(")[1].split(")")[0].strip()
            if idx in MAPPING:
                src = os.path.join(folder, f)
                dst = os.path.join(folder, MAPPING[idx])
                make_background_transparent(src, dst)
    print("All processed successfully!")
