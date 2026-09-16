import os
from PIL import Image

def generate_biome_overlays():
    base_dir = "Assets/terrain_atlas/base"
    masks_dir = "Assets/terrain_atlas/masks"
    overlays_dir = "Assets/terrain_atlas/overlays"
    
    biomes = ["plains", "meadow", "savanna", "dirt", "sand", "swamp", "hills", "mountains", "snow", "snow_peaks", "water_shallow", "water_deep", "farm_plowed", "farm_crops", "farm_wheat", "cobblestone"]
    masks = [
        "edge_n", "edge_s", "edge_w", "edge_e",
        "corner_outer_nw", "corner_outer_ne", "corner_outer_sw", "corner_outer_se",
        "corner_inner_nw", "corner_inner_ne", "corner_inner_sw", "corner_inner_se"
    ]
    
    for b in biomes:
        base_path = f"{base_dir}/{b}.png"
        if not os.path.exists(base_path):
            continue
        base_img = Image.open(base_path).convert("RGBA")
        b_out = f"{overlays_dir}/{b}"
        os.makedirs(b_out, exist_ok=True)
        
        for m_name in masks:
            mask_path = f"{masks_dir}/{m_name}.png"
            if not os.path.exists(mask_path):
                continue
            mask_img = Image.open(mask_path).convert("RGBA")
            
            overlay_img = base_img.copy()
            for y in range(64):
                for x in range(64):
                    p = base_img.getpixel((x, y))
                    m = mask_img.getpixel((x, y))
                    # Mask alpha controls opacity
                    overlay_img.putpixel((x, y), (p[0], p[1], p[2], m[3]))
            
            overlay_img.save(f"{b_out}/{m_name}.png")
            
    print("All biome overlays generated successfully!")

if __name__ == "__main__":
    generate_biome_overlays()
