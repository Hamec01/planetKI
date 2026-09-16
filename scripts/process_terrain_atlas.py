import os
from PIL import Image, ImageFilter

def make_seamless(img, blend_width=12):
    """Creates a seamless tile by blending opposite borders."""
    w, h = img.size
    result = img.copy()
    
    # Horizontal blend
    for x in range(blend_width):
        alpha = x / float(blend_width)
        for y in range(h):
            p_left = img.getpixel((x, y))
            p_right = img.getpixel((w - blend_width + x, y))
            
            blended_left = tuple(int((1 - alpha) * p_right[i] + alpha * p_left[i]) for i in range(len(p_left)))
            blended_right = tuple(int(alpha * p_right[i] + (1 - alpha) * p_left[i]) for i in range(len(p_right)))
            
            result.putpixel((x, y), blended_left)
            result.putpixel((w - blend_width + x, y), blended_right)
            
    # Vertical blend
    for y in range(blend_width):
        alpha = y / float(blend_width)
        for x in range(w):
            p_top = result.getpixel((x, y))
            p_bottom = result.getpixel((x, h - blend_width + y))
            
            blended_top = tuple(int((1 - alpha) * p_bottom[i] + alpha * p_top[i]) for i in range(len(p_top)))
            blended_bottom = tuple(int(alpha * p_bottom[i] + (1 - alpha) * p_top[i]) for i in range(len(p_top)))
            
            result.putpixel((x, y), blended_top)
            result.putpixel((x, h - blend_width + y), blended_bottom)
            
    return result

def main():
    atlas_path = r"C:\Users\Ham_h\.gemini\antigravity-ide\brain\14f72143-5c6c-4f6c-9abc-8bd249096145\.user_uploaded\media_1789587622552.jpg"
    if not os.path.exists(atlas_path):
        print("Error: Atlas image not found at", atlas_path)
        return

    atlas = Image.open(atlas_path).convert("RGBA")
    w, h = atlas.size
    print(f"Loaded atlas: {w}x{h}")

    base_out = "Assets/terrain_atlas"
    os.makedirs(f"{base_out}/base", exist_ok=True)
    os.makedirs(f"{base_out}/transitions", exist_ok=True)
    os.makedirs(f"{base_out}/rivers", exist_ok=True)

    # 1. Base Biome Tiles (64x64)
    # Row 1: Dirt (y: 64..128)
    dirt_tile = make_seamless(atlas.crop((64, 64, 128, 128)))
    dirt_tile.save(f"{base_out}/base/dirt.png")
    dirt_alt = make_seamless(atlas.crop((192, 64, 256, 128)))
    dirt_alt.save(f"{base_out}/base/dirt_alt.png")

    # Row 2: Meadow (col 0..7), Savanna (col 8..15) (y: 128..192)
    meadow_tile = make_seamless(atlas.crop((64, 128, 128, 192)))
    meadow_tile.save(f"{base_out}/base/meadow.png")
    plains_tile = make_seamless(atlas.crop((192, 128, 256, 192)))
    plains_tile.save(f"{base_out}/base/plains.png")
    savanna_tile = make_seamless(atlas.crop((576, 128, 640, 192)))
    savanna_tile.save(f"{base_out}/base/savanna.png")

    # Row 3: Sand (y: 192..256)
    sand_tile = make_seamless(atlas.crop((64, 192, 128, 256)))
    sand_tile.save(f"{base_out}/base/sand.png")
    sand_alt = make_seamless(atlas.crop((576, 192, 640, 256)))
    sand_alt.save(f"{base_out}/base/sand_alt.png")

    # Row 4: Snow (col 0..7), Ice/Stone (col 8..15) (y: 256..320)
    snow_tile = make_seamless(atlas.crop((64, 256, 128, 320)))
    snow_tile.save(f"{base_out}/base/snow.png")
    snow_peaks = make_seamless(atlas.crop((192, 256, 256, 320)))
    snow_peaks.save(f"{base_out}/base/snow_peaks.png")
    stone_tile = make_seamless(atlas.crop((576, 256, 640, 320)))
    stone_tile.save(f"{base_out}/base/stone.png")
    mountains_tile = make_seamless(atlas.crop((704, 256, 768, 320)))
    mountains_tile.save(f"{base_out}/base/mountains.png")

    # Row 5: Farmland (plowed, crops, wheat) (y: 320..384)
    farm_plowed = make_seamless(atlas.crop((64, 320, 128, 384)))
    farm_plowed.save(f"{base_out}/base/farm_plowed.png")
    farm_crops = make_seamless(atlas.crop((576, 320, 640, 384)))
    farm_crops.save(f"{base_out}/base/farm_crops.png")
    farm_wheat = make_seamless(atlas.crop((832, 320, 896, 384)))
    farm_wheat.save(f"{base_out}/base/farm_wheat.png")

    # Row 6: Water (River/Shallow col 0..7, Ocean/Deep col 8..15) (y: 384..448)
    water_shallow = make_seamless(atlas.crop((64, 384, 128, 448)))
    water_shallow.save(f"{base_out}/base/water_shallow.png")
    water_deep = make_seamless(atlas.crop((576, 384, 640, 448)))
    water_deep.save(f"{base_out}/base/water_deep.png")

    # Row 7: Cobblestone (col 0..7), Swamp (col 8..15) (y: 448..512)
    cobble_tile = make_seamless(atlas.crop((64, 448, 128, 512)))
    cobble_tile.save(f"{base_out}/base/cobblestone.png")
    swamp_tile = make_seamless(atlas.crop((576, 448, 640, 512)))
    swamp_tile.save(f"{base_out}/base/swamp.png")

    # 2. Extract Transitions (Grass to Dirt, Sand, Snow, and Water to Grass)
    transitions_map = {
        "grass_dirt": (512, 640),
        "grass_sand": (640, 768),
        "grass_snow": (768, 896),
        "water_grass": (896, 1024)
    }

    for name, (y_start, y_end) in transitions_map.items():
        t_dir = f"{base_out}/transitions/{name}"
        os.makedirs(t_dir, exist_ok=True)
        idx = 0
        for row_offset in [0, 64]:
            cur_y = y_start + row_offset
            for col in range(16):
                tile = atlas.crop((col * 64, cur_y, (col + 1) * 64, cur_y + 64))
                tile.save(f"{t_dir}/tile_{idx:02d}.png")
                idx += 1

    print("Terrain atlas extracted and processed successfully!")

if __name__ == "__main__":
    main()
