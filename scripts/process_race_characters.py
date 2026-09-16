import os
from PIL import Image

def extract_race_characters():
    races = {
        "desert": r"C:\Users\Ham_h\.gemini\antigravity-ide\brain\14f72143-5c6c-4f6c-9abc-8bd249096145\.user_uploaded\media_1789589393908.jpg",
        "savanna": r"C:\Users\Ham_h\.gemini\antigravity-ide\brain\14f72143-5c6c-4f6c-9abc-8bd249096145\.user_uploaded\media_1789589397718.jpg",
        "north": r"C:\Users\Ham_h\.gemini\antigravity-ide\brain\14f72143-5c6c-4f6c-9abc-8bd249096145\.user_uploaded\media_1789589471870.jpg"
    }

    role_matrix = [
        # Row 0: Управление и вера
        ["leader_m", "leader_f", "sage_m", "sage_f", "priest_m", "priest_f", "elder_m", "elder_f"],
        # Row 1: Добыча пищи
        ["forager_m", "forager_f", "hunter_m", "hunter_f", "farmer_m", "farmer_f", "fisherman_m", "fisherman_f"],
        # Row 2: Материалы и строительство
        ["woodcutter_m", "woodcutter_f", "mason_m", "mason_f", "miner_m", "miner_f", "builder_m", "builder_f"],
        # Row 3: Ремесло и жители
        ["blacksmith_m", "potter_f", "potter_m", "weaver_f", "villager_brown_m", "villager_green_f", "villager_blue_m", "villager_red_f"],
        # Row 4: Военные роли
        ["warrior_m", "warrior_f", "guard_m", "guard_f", "archer_m", "archer_f", "spearman_m", "spearman_f"],
        # Row 5: Командиры и взрослые
        ["commander_m", "commander_f", "veteran_m", "veteran_f", "adult_1", "adult_2", "adult_3", "adult_4"],
        # Row 6: Дети и подростки
        ["child_boy_1", "child_girl_1", "child_boy_2", "child_girl_2", "teen_boy_1", "teen_boy_2", "teen_girl_1", "teen_girl_2"],
        # Row 7: Пожилые и семьи
        ["grandpa_staff", "grandma", "elder_citizen_m", "elder_citizen_f", "senior_m", "senior_f", "mother_baby", "father_baby"]
    ]

    base_out = "Assets/characters"
    
    for race_id, img_path in races.items():
        if not os.path.exists(img_path):
            print(f"Error: {img_path} not found")
            continue
            
        sheet = Image.open(img_path).convert("RGBA")
        race_dir = f"{base_out}/{race_id}"
        os.makedirs(race_dir, exist_ok=True)
        
        char_idx = 0
        for r in range(8):
            for c in range(8):
                name = role_matrix[r][c]
                box = (c * 128, r * 128, (c + 1) * 128, (r + 1) * 128)
                char_img = sheet.crop(box)
                
                # Make black background transparent
                # Pixels near pure black (r < 15, g < 15, b < 15) become transparent
                clean_img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
                for y in range(128):
                    for x in range(128):
                        p = char_img.getpixel((x, y))
                        brightness = max(p[0], p[1], p[2])
                        if brightness < 15:
                            # Black background
                            clean_img.putpixel((x, y), (0, 0, 0, 0))
                        elif brightness < 35:
                            # Soft edge alpha
                            alpha = int(255 * (brightness - 15) / 20.0)
                            clean_img.putpixel((x, y), (p[0], p[1], p[2], alpha))
                        else:
                            clean_img.putpixel((x, y), p)
                            
                clean_img.save(f"{race_dir}/{name}.png")
                # Also save with 0-indexed number for sequential access
                clean_img.save(f"{race_dir}/char_{char_idx:02d}.png")
                char_idx += 1
                
        print(f"Extracted 64 characters for race: {race_id}")

if __name__ == "__main__":
    extract_race_characters()
