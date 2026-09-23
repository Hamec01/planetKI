import os
import glob
from PIL import Image
from collections import deque

def make_background_transparent(img_path):
    img = Image.open(img_path).convert("RGBA")
    w, h = img.size
    pixels = img.load()
    
    # Check corner pixels
    corners = [pixels[0, 0], pixels[w - 1, 0], pixels[0, h - 1], pixels[w - 1, h - 1]]
    print(f"{os.path.basename(img_path)} size: {w}x{h}, corners: {corners}")
    
    # BFS flood fill from all border pixels that are near black (r<20, g<20, b<20)
    visited = set()
    queue = deque()
    
    def is_black(x, y, threshold=20):
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
                if (nx, ny) not in visited and is_black(nx, ny, 25):
                    visited.add((nx, ny))
                    queue.append((nx, ny))
                    
    # Make all visited background pixels fully transparent
    for (x, y) in visited:
        r, g, b, a = pixels[x, y]
        pixels[x, y] = (r, g, b, 0)
        
    # Soft edge feathering for boundary pixels (pixels next to visited with low brightness)
    border_visited = set()
    for (x, y) in visited:
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)]:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in visited:
                border_visited.add((nx, ny))
                
    for (x, y) in border_visited:
        r, g, b, a = pixels[x, y]
        max_val = max(r, g, b)
        if max_val < 35:
            # Smoothly attenuate alpha
            factor = max(0.0, min(1.0, (max_val - 10) / 25.0))
            pixels[x, y] = (r, g, b, int(a * factor))
            
    img.save(img_path, "PNG")
    print(f"Successfully transparent: {os.path.basename(img_path)}")

if __name__ == "__main__":
    folder = r"E:\Planetki\Assets\buildings\Dom_roda"
    pngs = glob.glob(os.path.join(folder, "*.png"))
    for p in pngs:
        make_background_transparent(p)
