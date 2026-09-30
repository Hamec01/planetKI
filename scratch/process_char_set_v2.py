import os
from PIL import Image

SRC_DIR = r"E:\Planetki\Assets\characters\char_set_v2"
OUT_BASE = r"E:\Planetki\Assets\characters"

SHEET_CONFIG = [
    {
        "id": "01_leadership_faith",
        "roles": [
            ("leader_m", "m", "adult"),
            ("leader_f", "f", "adult"),
            ("sage_m", "m", "adult"),
            ("sage_f", "f", "adult"),
            ("priest_m", "m", "adult"),
            ("priest_f", "f", "adult"),
            ("elder_m", "m", "elder"),
            ("elder_f", "f", "elder"),
        ]
    },
    {
        "id": "02_food_gathering",
        "roles": [
            ("forager_m", "m", "adult"),
            ("forager_f", "f", "adult"),
            ("hunter_m", "m", "adult"),
            ("hunter_f", "f", "adult"),
            ("farmer_m", "m", "adult"),
            ("farmer_f", "f", "adult"),
            ("fisherman_m", "m", "adult"),
            ("fisherman_f", "f", "adult"),
        ]
    },
    {
        "id": "03_materials_building",
        "roles": [
            ("woodcutter_m", "m", "adult"),
            ("woodcutter_f", "f", "adult"),
            ("mason_m", "m", "adult"),
            ("mason_f", "f", "adult"),
            ("miner_m", "m", "adult"),
            ("miner_f", "f", "adult"),
            ("builder_m", "m", "adult"),
            ("builder_f", "f", "adult"),
        ]
    },
    {
        "id": "04_crafts_civilians",
        "roles": [
            ("blacksmith_m", "m", "adult"),
            ("potter_f", "f", "adult"),
            ("potter_m", "m", "adult"),
            ("weaver_f", "f", "adult"),
            ("villager_brown_m", "m", "adult"),
            ("villager_green_f", "f", "adult"),
            ("villager_blue_m", "m", "adult"),
            ("villager_red_f", "f", "adult"),
        ]
    },
    {
        "id": "05_military_roles",
        "roles": [
            ("warrior_m", "m", "adult"),
            ("warrior_f", "f", "adult"),
            ("guard_m", "m", "adult"),
            ("guard_f", "f", "adult"),
            ("archer_m", "m", "adult"),
            ("archer_f", "f", "adult"),
            ("spearman_m", "m", "adult"),
            ("spearman_f", "f", "adult"),
        ]
    },
    {
        "id": "06_commanders_adults",
        "roles": [
            ("commander_m", "m", "adult"),
            ("commander_f", "f", "adult"),
            ("veteran_m", "m", "adult"),
            ("veteran_f", "f", "adult"),
            ("adult_1", "m", "adult"),
            ("adult_2", "f", "adult"),
            ("adult_3", "m", "adult"),
            ("adult_4", "f", "adult"),
        ]
    },
    {
        "id": "07_children_teenagers",
        "roles": [
            ("child_boy_1", "m", "child"),
            ("child_boy_2", "m", "child"),
            ("child_girl_1", "f", "child"),
            ("child_girl_2", "f", "child"),
            ("teen_boy_1", "m", "youth"),
            ("teen_boy_2", "m", "youth"),
            ("teen_girl_1", "f", "youth"),
            ("teen_girl_2", "f", "youth"),
        ]
    },
    {
        "id": "08_elderly_families",
        "roles": [
            ("grandpa_staff", "m", "elder"),
            ("grandma", "f", "elder"),
            ("elder_citizen_m", "m", "elder"),
            ("elder_citizen_f", "f", "elder"),
            ("senior_m", "m", "elder"),
            ("senior_f", "f", "elder"),
            ("mother_baby", "f", "adult"),
            ("father_baby", "m", "adult"),
        ]
    },
]

# Standard target heights on 128x128 canvas (baseline y=122)
TARGET_HEIGHTS = {
    "adult": 98.0,
    "elder": 92.0,
    "youth": 82.0,
    "child": 66.0
}

def find_seams(img, num_chars=8):
    W, H = img.size
    alpha = img.getchannel("A")
    alpha_data = alpha.load()
    
    seams = [[0] * H] # left edge
    nominal_w = W / float(num_chars)
    
    for i in range(1, num_chars):
        nominal_x = int(round(i * nominal_w))
        x_min = max(0, nominal_x - 55)
        x_max = min(W - 1, nominal_x + 55)
        win_w = x_max - x_min + 1
        
        # DP table: dp[y][x_rel]
        dp = [0.0] * win_w
        for x_rel in range(win_w):
            a = alpha_data[x_min + x_rel, 0]
            dp[x_rel] = (a / 255.0) ** 2 * 1000.0 + 1.0
            
        backtrack = []
        
        for y in range(1, H):
            new_dp = [0.0] * win_w
            bt_row = [0] * win_w
            for x_rel in range(win_w):
                a = alpha_data[x_min + x_rel, y]
                cost = (a / 255.0) ** 2 * 1000.0 + 1.0
                
                best_prev = dp[x_rel]
                best_offset = 0
                if x_rel > 0 and dp[x_rel - 1] < best_prev:
                    best_prev = dp[x_rel - 1]
                    best_offset = -1
                if x_rel < win_w - 1 and dp[x_rel + 1] < best_prev:
                    best_prev = dp[x_rel + 1]
                    best_offset = 1
                    
                new_dp[x_rel] = cost + best_prev
                bt_row[x_rel] = x_rel + best_offset
            dp = new_dp
            backtrack.append(bt_row)
            
        best_end = 0
        min_val = dp[0]
        for x_rel in range(1, win_w):
            if dp[x_rel] < min_val:
                min_val = dp[x_rel]
                best_end = x_rel
                
        seam_path = [0] * H
        seam_path[H - 1] = best_end + x_min
        cur = best_end
        for y in range(H - 2, -1, -1):
            cur = backtrack[y][cur]
            seam_path[y] = cur + x_min
            
        seams.append(seam_path)
        
    seams.append([W - 1] * H)
    return seams

def extract_character(img, left_seam, right_seam):
    W, H = img.size
    
    min_x, max_x = W, 0
    min_y, max_y = H, 0
    alpha = img.getchannel("A").load()
    
    found_any = False
    for y in range(H):
        x1 = left_seam[y]
        x2 = right_seam[y]
        for x in range(x1, min(x2 + 1, W)):
            if alpha[x, y] > 5:
                found_any = True
                if x < min_x: min_x = x
                if x > max_x: max_x = x
                if y < min_y: min_y = y
                if y > max_y: max_y = y
                
    if not found_any or max_x < min_x or max_y < min_y:
        return None
        
    cw = max_x - min_x + 1
    ch = max_y - min_y + 1
    
    char_img = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    char_pixels = char_img.load()
    src_pixels = img.load()
    
    for y in range(min_y, max_y + 1):
        x1 = left_seam[y]
        x2 = right_seam[y]
        for x in range(max(min_x, x1), min(max_x + 1, x2 + 1)):
            if alpha[x, y] > 5:
                char_pixels[x - min_x, y - min_y] = src_pixels[x, y]
                
    return char_img

def scale_and_place(char_img, role_name, cohort, target_size=128, baseline_y=122):
    cw, ch = char_img.size
    
    target_h = TARGET_HEIGHTS.get(cohort, 98.0)
    
    # Spear accounts for ~12% extra height above character head
    effective_body_h = float(ch)
    if "spearman" in role_name:
        effective_body_h = ch * 0.88
        
    scale = target_h / effective_body_h
    
    new_w = max(1, int(round(cw * scale)))
    new_h = max(1, int(round(ch * scale)))
    
    # Prevent exceeding top edge (padding >= 4px)
    if new_h > baseline_y - 4:
        re_scale = float(baseline_y - 4) / float(new_h)
        new_w = max(1, int(round(new_w * re_scale)))
        new_h = baseline_y - 4
        
    scaled_img = char_img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    
    canvas = Image.new("RGBA", (target_size, target_size), (0, 0, 0, 0))
    paste_x = (target_size - new_w) // 2
    paste_y = baseline_y - new_h
    
    canvas.paste(scaled_img, (paste_x, paste_y), scaled_img)
    return canvas

def process_all():
    summary_records = []
    
    for cat_idx, cat in enumerate(SHEET_CONFIG):
        sheet_id = cat["id"]
        roles = cat["roles"]
        
        patterns = {
            "north": os.path.join(SRC_DIR, f"{sheet_id}.png"),
            "savanna": os.path.join(SRC_DIR, f"{sheet_id}_b.png"),
            "desert": os.path.join(SRC_DIR, f"{sheet_id}_c.png"),
        }
        
        if not os.path.exists(patterns["desert"]):
            patterns["desert"] = patterns["savanna"]
            
        for race, sheet_path in patterns.items():
            out_race_dir = os.path.join(OUT_BASE, race)
            os.makedirs(out_race_dir, exist_ok=True)
            
            if not os.path.exists(sheet_path):
                print(f"Warning: {sheet_path} does not exist!")
                continue
                
            print(f"Processing {sheet_id} [{race}] with cohort normalization...")
            sheet_img = Image.open(sheet_path).convert("RGBA")
            seams = find_seams(sheet_img, num_chars=8)
            
            for i in range(8):
                role_name, gender, cohort = roles[i]
                char_num = cat_idx * 8 + i
                char_num_str = f"char_{char_num:02d}"
                
                left_seam = seams[i]
                right_seam = seams[i + 1]
                
                char_crop = extract_character(sheet_img, left_seam, right_seam)
                if char_crop is None:
                    print(f"Error: Empty crop for {sheet_id} {race} #{i}")
                    continue
                    
                final_sprite = scale_and_place(char_crop, role_name, cohort)
                
                # Save named role
                named_path = os.path.join(out_race_dir, f"{role_name}.png")
                final_sprite.save(named_path, "PNG")
                
                # Save numbered alias
                numbered_path = os.path.join(out_race_dir, f"{char_num_str}.png")
                final_sprite.save(numbered_path, "PNG")
                
                summary_records.append({
                    "race": race,
                    "cat": sheet_id,
                    "role": role_name,
                    "gender": gender,
                    "cohort": cohort,
                    "final_bbox": final_sprite.getbbox()
                })
                
    print(f"\nSuccessfully normalized and generated {len(summary_records)} character instances!")

if __name__ == "__main__":
    process_all()
