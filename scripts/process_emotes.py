import os
from PIL import Image

src_path = r'C:\Users\Ham_h\.gemini\antigravity-ide\brain\db1f7cd6-d23e-48e6-a3d5-ef24ab26b38a\.user_uploaded\media_1790092251971.png'
if not os.path.exists(src_path):
    src_path = r'C:\Users\Ham_h\Downloads\ChatGPT Image 22 сент. 2026 г., 18_53_54.png'

img = Image.open(src_path).convert('RGBA')
w, h = img.size
pixels = img.load()

visited = [[False]*h for _ in range(w)]
components = []
for y in range(h):
    for x in range(w):
        if pixels[x, y][3] > 20 and not visited[x][y]:
            queue = [(x, y)]
            visited[x][y] = True
            min_x, max_x = x, x
            min_y, max_y = y, y
            head = 0
            while head < len(queue):
                cx, cy = queue[head]
                head += 1
                min_x = min(min_x, cx)
                max_x = max(max_x, cx)
                min_y = min(min_y, cy)
                max_y = max(max_y, cy)
                
                for dx, dy in [(-1,0), (1,0), (0,-1), (0,1)]:
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h and not visited[nx][ny]:
                        if pixels[nx, ny][3] > 20:
                            visited[nx][ny] = True
                            queue.append((nx, ny))
            
            # Keep components with > 200 pixels
            if len(queue) > 200:
                components.append({
                    'bbox': (min_x, min_y, max_x + 1, max_y + 1),
                    'size': (max_x - min_x + 1, max_y - min_y + 1),
                    'center': ((min_x + max_x) / 2.0, (min_y + max_y) / 2.0),
                    'pixels': queue,
                    'count': len(queue)
                })

print(f"Total components found: {len(components)}")
for i, c in enumerate(components):
    bx = c['bbox']
    cnt = c['center']
    print(f"Comp {i:2d}: count={c['count']:5d}, center=({cnt[0]:5.1f}, {cnt[1]:5.1f}), bbox={bx}")
