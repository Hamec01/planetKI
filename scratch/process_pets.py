import os
from PIL import Image

SRC_PATH = r"E:\Planetki\ChatGPT Image 22 сент. 2026 г., 22_20_37.png"
OUT_ANIMALS = r"E:\Planetki\Assets\animals"
OUT_CAMP = r"E:\Planetki\Assets\buildings\dom_ohotnika"

os.makedirs(OUT_ANIMALS, exist_ok=True)
os.makedirs(OUT_CAMP, exist_ok=True)

img = Image.open(SRC_PATH).convert("RGBA")

# 6 animal crop boxes
ANIMALS = [
    # Top row (Dogs)
    ("dog_hound", (0, 0, 512, 535)),
    ("dog_wolf", (512, 0, 1012, 535)),
    ("dog_shepherd", (1012, 0, 1536, 535)),
    # Bottom row (Cats)
    ("cat_ginger", (0, 535, 512, 1024)),
    ("cat_tuxedo", (512, 535, 1012, 1024)),
    ("cat_tabby", (1012, 535, 1536, 1024)),
]

def make_centered_sprite(crop_img, target_size=128, target_h=96, baseline_y=122):
    bbox = crop_img.getchannel("A").getbbox()
    if not bbox:
        return None
    tight = crop_img.crop(bbox)
    tw, th = tight.size
    
    scale = float(target_h) / float(th)
    new_w = max(1, int(round(tw * scale)))
    new_h = max(1, int(round(th * scale)))
    
    scaled = tight.resize((new_w, new_h), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (target_size, target_size), (0, 0, 0, 0))
    paste_x = (target_size - new_w) // 2
    paste_y = baseline_y - new_h
    canvas.paste(scaled, (paste_x, paste_y), scaled)
    return canvas

for name, box in ANIMALS:
    sub = img.crop(box)
    
    # Dogs: target height = 88 px (pets are smaller than humans who are 98 px)
    # Cats: target height = 72 px
    is_dog = "dog" in name
    th = 86 if is_dog else 72
    sprite = make_centered_sprite(sub, target_size=128, target_h=th, baseline_y=122)
    
    out_p = os.path.join(OUT_ANIMALS, f"{name}.png")
    sprite.save(out_p, "PNG")
    print(f"Saved {name}.png to {out_p}")
    
    # Also save aliases
    if name == "dog_wolf":
        sprite.save(os.path.join(OUT_ANIMALS, "dog.png"), "PNG")
        sprite.save(os.path.join(OUT_ANIMALS, "dog_hunting.png"), "PNG")
        # Save for hunting camp building upgrade prop
        sprite.save(os.path.join(OUT_CAMP, "hunt_dogs.png"), "PNG")
        print("Saved hunt_dogs.png to dom_ohotnika")
    elif name == "cat_ginger":
        sprite.save(os.path.join(OUT_ANIMALS, "cat.png"), "PNG")

print("All pets processed successfully!")
