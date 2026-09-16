import os
from PIL import Image

def extract_nature():
    sheet_path = r"C:\Users\Ham_h\.gemini\antigravity-ide\brain\14f72143-5c6c-4f6c-9abc-8bd249096145\.user_uploaded\media_1789590910181.jpg"
    if not os.path.exists(sheet_path):
        print("Error: Nature sheet not found")
        return
        
    sheet = Image.open(sheet_path).convert("RGBA")
    out_dir = "Assets/nature_v2"
    os.makedirs(out_dir, exist_ok=True)
    
    matrix = [
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
    
    for r in range(8):
        for c in range(8):
            name = matrix[r][c]
            box = (c * 128, r * 128, (c + 1) * 128, (r + 1) * 128)
            sprite = sheet.crop(box)
            
            # Make black background transparent with soft edge
            clean_sprite = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
            for y in range(128):
                for x in range(128):
                    p = sprite.getpixel((x, y))
                    brightness = max(p[0], p[1], p[2])
                    if brightness < 15:
                        clean_sprite.putpixel((x, y), (0, 0, 0, 0))
                    elif brightness < 35:
                        alpha = int(255 * (brightness - 15) / 20.0)
                        clean_sprite.putpixel((x, y), (p[0], p[1], p[2], alpha))
                    else:
                        clean_sprite.putpixel((x, y), p)
                        
            clean_sprite.save(f"{out_dir}/{name}.png")
            
    print("Successfully extracted 64 nature sprites into Assets/nature_v2!")

if __name__ == "__main__":
    extract_nature()
