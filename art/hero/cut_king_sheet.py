# Нарезка и стабилизация листа Короля:
# python art/hero/cut_king_sheet.py [путь_к_исходнику]
# Выход: art/hero/king_sheet.png (16 колонок x 15 рядов, 64x36)
import sys, os, glob
import numpy as np
from PIL import Image
from collections import deque

src_path = sys.argv[1] if len(sys.argv) > 1 else 'C:/Users/Ham_h/Downloads/king aron -table-427-240.png'
if not os.path.exists(src_path):
    candidates = [
        'art/hero/king_sheet_1.webp',
        'Assets/char/spritesheet-table-427-240 (3).png',
        'C:/Users/Ham_h/Downloads/king aron -table-427-240.png'
    ]
    for c in candidates:
        if os.path.exists(c):
            src_path = c
            break

print(f'Using source: {src_path}')
im = Image.open(src_path).convert('RGB')
im_arr = np.array(im).astype(np.float32)
H, W, _ = im_arr.shape
ROWS, COLS = 15, 16
CW = W // COLS
CH = H // ROWS

OUT_W, OUT_H = 64, 36
FOOT_Y = 32

def clean_cell(cell_rgb):
    h, w, _ = cell_rgb.shape
    border = np.concatenate([cell_rgb[0], cell_rgb[-1], cell_rgb[:,0], cell_rgb[:,-1]])
    bg = np.median(border, axis=0)
    
    is_green = bg[1] > bg[0] + 15
    is_gray = (bg.max() - bg.min()) < 20
    
    diff = cell_rgb - bg[None, None, :]
    dist = np.sqrt((diff**2).sum(axis=2))
    
    if is_green:
        green_dom = (cell_rgb[:,:,1] > cell_rgb[:,:,0] + 10) & (cell_rgb[:,:,1] > cell_rgb[:,:,2] + 10)
        dist = np.where(green_dom & (dist < 85), 0.0, dist)
    elif is_gray:
        sat = cell_rgb.max(axis=2) - cell_rgb.min(axis=2)
        val = cell_rgb.max(axis=2)
        halo = (sat < 18) & (val >= bg.max() - 25)
        dist = np.where(halo, 0.0, np.where(sat < 12, dist * 3.0, dist))
        
    bgmask = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h-1):
            if dist[y, x] < 55 and not bgmask[y, x]:
                bgmask[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w-1):
            if dist[y, x] < 55 and not bgmask[y, x]:
                bgmask[y, x] = True
                q.append((y, x))
                
    while q:
        y, x = q.popleft()
        for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
            ny, nx = y+dy, x+dx
            if 0 <= ny < h and 0 <= nx < w and not bgmask[ny, nx] and dist[ny, nx] < 55:
                bgmask[ny, nx] = True
                q.append((ny, nx))
                
    alpha = np.where(bgmask, 0.0, 255.0)
    fg = ~bgmask
    
    edge = fg & (np.roll(bgmask,1,0)|np.roll(bgmask,-1,0)|np.roll(bgmask,1,1)|np.roll(bgmask,-1,1))
    a_edge = np.clip((dist - 20) / 45.0, 0, 1) * 255.0
    alpha[edge] = a_edge[edge]
    
    lab = np.zeros((h, w), np.int32)
    n = 0
    sizes = {}
    for y in range(h):
        for x in range(w):
            if alpha[y, x] > 0 and lab[y, x] == 0:
                n += 1
                stack = [(y, x)]
                lab[y, x] = n
                cnt = 0
                while stack:
                    cy, cx = stack.pop()
                    cnt += 1
                    for dy in (-1,0,1):
                        for dx in (-1,0,1):
                            ny, nx = cy+dy, cx+dx
                            if 0 <= ny < h and 0 <= nx < w and lab[ny, nx] == 0 and alpha[ny, nx] > 0:
                                lab[ny, nx] = n
                                stack.append((ny, nx))
                sizes[n] = cnt
    for k, sz in sizes.items():
        if sz < 25:
            alpha[lab == k] = 0.0
            
    rgb = cell_rgb.copy()
    af = (alpha / 255.0)[..., None]
    semi = (alpha > 0) & (alpha < 255)
    un = (rgb - (1.0 - af) * bg[None, None, :]) / np.maximum(af, 0.15)
    rgb = np.where(semi[..., None], np.clip(un, 0, 255), rgb)
    
    if is_green:
        mx = np.maximum(rgb[..., 0], rgb[..., 2])
        rgb[..., 1] = np.where(edge, np.minimum(rgb[..., 1], mx + 10), rgb[..., 1])
        
    alpha[:2, :] = 0
    alpha[-2:, :] = 0
    alpha[:, :2] = 0
    alpha[:, -2:] = 0
    
    return np.dstack([rgb, alpha])

print('Extracting and cleaning cells...')
cleaned_sheet = []
for r in range(ROWS):
    row_cleaned = []
    for c in range(COLS):
        cell_raw = im_arr[r*CH:(r+1)*CH, c*CW:(c+1)*CW]
        row_cleaned.append(clean_cell(cell_raw))
    cleaned_sheet.append(row_cleaned)

out_sheet = Image.new('RGBA', (OUT_W * COLS, OUT_H * ROWS), (0, 0, 0, 0))

for r in range(ROWS):
    feet_ys = []
    spine_xs = []
    for c in range(COLS):
        rgba = cleaned_sheet[r][c]
        a = rgba[:, :, 3]
        ys, xs = np.where(a > 20)
        if len(ys) > 50:
            feet_ys.append(ys.max())
            spine_xs.append((xs.min() + xs.max()) / 2.0)
            
    ref_feet_y = np.median(feet_ys) if feet_ys else (CH - 15)
    ref_spine_x = np.median(spine_xs) if spine_xs else (CW / 2.0)
    scale = 27.0 / 206.0
    
    for c in range(COLS):
        rgba = cleaned_sheet[r][c]
        cell_img = Image.fromarray(rgba.astype(np.uint8), 'RGBA')
        new_w = int(round(CW * scale))
        new_h = int(round(CH * scale))
        resized_cell = cell_img.resize((new_w, new_h), Image.LANCZOS)
        
        target_anchor_x = OUT_W // 2
        target_anchor_y = FOOT_Y
        
        scaled_anchor_x = int(round(ref_spine_x * scale))
        scaled_anchor_y = int(round(ref_feet_y * scale))
        
        paste_x = target_anchor_x - scaled_anchor_x
        paste_y = target_anchor_y - scaled_anchor_y
        
        frame_canvas = Image.new('RGBA', (OUT_W, OUT_H), (0, 0, 0, 0))
        frame_canvas.paste(resized_cell, (paste_x, paste_y), resized_cell)
        out_sheet.paste(frame_canvas, (c * OUT_W, r * OUT_H))

# Color grade and tone match
ref_files = glob.glob('Assets/characters/north/*.png') + glob.glob('../../Assets/characters/north/*.png')
if ref_files:
    all_npc_rgb = []
    for p in ref_files:
        arr = np.array(Image.open(p).convert('RGBA'))
        mask = arr[:,:,3] > 20
        if mask.sum() > 0:
            all_npc_rgb.append(arr[mask][:, :3])
    if all_npc_rgb:
        ref_pixels = np.vstack(all_npc_rgb).astype(np.float32)
        k_arr = np.array(out_sheet)
        alpha = k_arr[:, :, 3]
        mask = alpha > 10
        k_pixels = k_arr[mask][:, :3].astype(np.float32)
        matched_rgb = np.zeros_like(k_arr[:, :, :3], dtype=np.float32)
        for ch in range(3):
            src_val = k_arr[:, :, ch].astype(np.float32)
            k_ch = k_pixels[:, ch]
            ref_ch = ref_pixels[:, ch]
            ref_sorted = np.sort(ref_ch)
            ranks = np.searchsorted(np.sort(k_ch), src_val) / float(len(k_ch))
            ranks = np.clip(ranks, 0.0, 1.0)
            ref_idx = (ranks * (len(ref_sorted) - 1)).astype(np.int32)
            matched_rgb[:, :, ch] = ref_sorted[ref_idx]
        norm = k_arr[:,:,:3].astype(np.float32) / 255.0
        gamma_rgb = np.power(norm, 1.7) * 255.0
        gamma_rgb[:,:,0] *= 0.95
        gamma_rgb[:,:,1] *= 0.88
        gamma_rgb[:,:,2] *= 0.78
        final_rgb = np.clip(0.7 * matched_rgb + 0.3 * gamma_rgb, 0, 255).astype(np.uint8)
        res_rgba = np.dstack([final_rgb, alpha])
        out_sheet = Image.fromarray(res_rgba, 'RGBA')

out_sheet.save('art/hero/king_sheet.png')
print('Successfully saved art/hero/king_sheet.png (1024x540)!')
