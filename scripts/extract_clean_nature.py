import os
import json
from PIL import Image
from collections import deque

def extract_all():
    sheet_path = r"C:\Users\Ham_h\.gemini\antigravity-ide\brain\14f72143-5c6c-4f6c-9abc-8bd249096145\.user_uploaded\media_1789590910181.jpg"
    img = Image.open(sheet_path).convert("RGBA")
    w, h = img.size

    mask = [[False]*w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            p = img.getpixel((x, y))
            if max(p[0], p[1], p[2]) > 20:
                mask[y][x] = True

    visited = [[False]*w for _ in range(h)]
    components = []

    for y in range(h):
        for x in range(w):
            if mask[y][x] and not visited[y][x]:
                q = deque([(x, y)])
                visited[y][x] = True
                pixels = []
                min_x, max_x = x, x
                min_y, max_y = y, y
                while q:
                    cx, cy = q.popleft()
                    pixels.append((cx, cy))
                    min_x = min(min_x, cx)
                    max_x = max(max_x, cx)
                    min_y = min(min_y, cy)
                    max_y = max(max_y, cy)
                    for dx, dy in [(-1,0),(1,0),(0,-1),(0,1)]:
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and mask[ny][nx] and not visited[ny][nx]:
                            visited[ny][nx] = True
                            q.append((nx, ny))
                if len(pixels) > 200:
                    components.append({
                        "bbox": (min_x, min_y, max_x + 1, max_y + 1),
                        "center": ((min_x + max_x)//2, (min_y + max_y)//2),
                        "pixels": set(pixels)
                    })

    print(f"Components found: {len(components)}")
    components.sort(key=lambda c: c["center"][1])

    matrix_names = [
        # Row 0: Лиственные деревья
        ["tree_oak", "tree_birch", "tree_maple_green", "tree_poplar", "tree_willow", "tree_young", "tree_autumn_red", "tree_birch_yellow"],
        # Row 1: Хвойные и зимние деревья
        ["tree_spruce", "tree_spruce_blue", "tree_pine", "tree_spruce_young", "tree_spruce_snow", "tree_pine_snow", "tree_bare", "tree_dead"],
        # Row 2: Кусты
        ["bush_round_green", "bush_spreading", "bush_light", "bush_dark", "bush_berries_red", "bush_berries_blue", "bush_flowers", "bush_dry_thorny"],
        # Row 3: Камни
        ["rock_small_pebbles", "rock_round_boulder", "rock_cliff_group", "rock_flat_slabs", "rock_mossy", "rock_red_stone", "rock_limestone", "rock_snow_boulder"],
        # Row 4: Трава и листья
        ["grass_tuft_low", "grass_dense", "grass_tall_meadow", "grass_thin", "grass_dry_yellow", "grass_steppe_orange", "plant_broadleaf", "plant_fern"],
        # Row 5: Цветы и лесные растения
        ["flowers_white", "flowers_yellow", "flowers_purple", "flowers_poppies", "mushrooms_flyagaric", "mushrooms_brown", "plant_dense_fern", "bush_berry_low"],
        # Row 6: Болотные и пустынные растения
        ["reeds", "cattails", "marsh_grass", "marsh_broadleaf", "water_lily", "cactus_branched", "cactus_round", "tumbleweed"],
        # Row 7: Лесные детали
        ["stump_fresh", "stump_mossy", "log_fallen", "branch_broken", "branches_pile", "leaves_fallen", "creeping_greens", "sapling"]
    ]

    out_dir = "Assets/nature_clean"
    os.makedirs(out_dir, exist_ok=True)
    metadata = {}

    for r in range(8):
        row_comps = components[r*8:(r+1)*8]
        row_comps.sort(key=lambda c: c["center"][0])
        for c in range(8):
            name = matrix_names[r][c]
            comp = row_comps[c]
            bx0, by0, bx1, by1 = comp["bbox"]
            cw = bx1 - bx0
            ch = by1 - by0

            # Create clean sprite with transparent background
            sprite = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
            for py in range(by0, by1):
                for px in range(bx0, bx1):
                    if (px, py) in comp["pixels"]:
                        p = img.getpixel((px, py))
                        brightness = max(p[0], p[1], p[2])
                        if brightness < 15:
                            sprite.putpixel((px - bx0, py - by0), (0, 0, 0, 0))
                        elif brightness < 35:
                            alpha = int(255 * (brightness - 15) / 20.0)
                            sprite.putpixel((px - bx0, py - by0), (p[0], p[1], p[2], alpha))
                        else:
                            sprite.putpixel((px - bx0, py - by0), p)

            sprite.save(f"{out_dir}/{name}.png")

            # Determine category, scale, and harvest resource
            is_winter = ("snow" in name) or (name in ["tree_bare", "tree_dead"])
            if r in [0, 1]:
                cat = "tree"
                scale_h = 44.0 if ("young" not in name) else 30.0
                harvest_res = "wood"
                harvest_stump = "stump_fresh" if not is_winter else "stump_mossy"
            elif r == 2:
                cat = "bush"
                scale_h = 22.0
                harvest_res = "food" if ("berries" in name or name == "bush_flowers") else None
                harvest_stump = None
            elif r == 3:
                cat = "rock"
                scale_h = 26.0 if ("cliff" in name or "flat" in name) else 20.0
                harvest_res = "stone"
                harvest_stump = "rock_small_pebbles"
            elif r == 4:
                cat = "grass"
                scale_h = 13.0
                harvest_res = None
                harvest_stump = None
            elif r == 5:
                cat = "flower_mushroom"
                scale_h = 14.0
                harvest_res = "food" if ("mushrooms" in name or "berry" in name) else None
                harvest_stump = None
            elif r == 6:
                cat = "marsh_desert"
                scale_h = 24.0 if ("cactus" in name or "reeds" in name or "cattails" in name) else 14.0
                harvest_res = "food" if "cactus" in name else None
                harvest_stump = None
            else:
                cat = "detail"
                scale_h = 12.0 if ("leaves" in name or "branch" in name) else 16.0
                harvest_res = "wood" if ("log" in name or "branch" in name) else None
                harvest_stump = None

            metadata[name] = {
                "category": cat,
                "scale_h": scale_h,
                "is_winter_only": is_winter,
                "harvest_resource": harvest_res,
                "harvest_stump": harvest_stump,
                "orig_size": [cw, ch]
            }

    with open(f"{out_dir}/nature_meta.json", "w", encoding="utf-8") as f:
        json.dump(metadata, f, ensure_ascii=False, indent=2)

    print("All 64 nature sprites cleanly extracted and categorized with metadata!")

if __name__ == "__main__":
    extract_all()
