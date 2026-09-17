from PIL import Image, ImageDraw

def create_hare():
    # 28x24 canvas
    img = Image.new("RGBA", (28, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    fur_main = (168, 134, 102, 255)
    fur_dark = (128, 98, 70, 255)
    fur_light = (220, 200, 180, 255)
    ear_pink = (230, 160, 170, 255)
    eye_dark = (30, 20, 20, 255)
    outline = (70, 50, 35, 255)
    
    # Body
    d.ellipse([7, 9, 21, 20], fill=fur_main, outline=outline)
    d.ellipse([9, 13, 19, 19], fill=fur_light) # belly
    
    # Head
    d.ellipse([16, 6, 25, 15], fill=fur_main, outline=outline)
    d.point((22, 9), fill=eye_dark)
    d.point((24, 12), fill=(100, 70, 60, 255)) # nose
    
    # Ears
    d.polygon([(18, 7), (16, 0), (19, 1), (20, 7)], fill=fur_main, outline=outline)
    d.line([(18, 2), (18, 6)], fill=ear_pink)
    d.polygon([(21, 7), (21, 1), (23, 2), (22, 7)], fill=fur_main, outline=outline)
    d.line([(22, 2), (22, 6)], fill=ear_pink)
    
    # Tail
    d.ellipse([5, 12, 8, 16], fill=fur_light, outline=outline)
    
    # Paws
    d.ellipse([8, 18, 13, 22], fill=fur_dark, outline=outline)
    d.ellipse([16, 18, 21, 22], fill=fur_dark, outline=outline)
    
    img.save("e:/Planetki/Assets/nature_clean/animal_hare.png")
    print("Hare sprite saved.")

def create_deer():
    # 36x36 canvas
    img = Image.new("RGBA", (36, 36), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    fur_body = (150, 95, 55, 255)
    fur_dark = (105, 65, 35, 255)
    fur_belly = (215, 185, 150, 255)
    antler_color = (195, 175, 140, 255)
    eye_color = (25, 20, 18, 255)
    outline = (65, 40, 25, 255)
    hoof_color = (40, 30, 25, 255)
    
    # Torso
    d.ellipse([8, 13, 26, 25], fill=fur_body, outline=outline)
    d.ellipse([11, 18, 23, 24], fill=fur_belly)
    
    # Neck & Chest
    d.polygon([(20, 15), (26, 7), (29, 9), (24, 20)], fill=fur_body, outline=outline)
    
    # Head
    d.ellipse([25, 4, 34, 13], fill=fur_body, outline=outline)
    d.point((30, 7), fill=eye_color)
    d.point((33, 10), fill=hoof_color) # snout
    
    # Antlers
    d.line([(27, 4), (25, 0)], fill=antler_color, width=1)
    d.line([(25, 0), (23, 1)], fill=antler_color, width=1)
    d.line([(25, 0), (26, -1)], fill=antler_color, width=1)
    d.line([(28, 4), (28, -1)], fill=antler_color, width=1)
    d.line([(28, 1), (30, 0)], fill=antler_color, width=1)
    
    # Legs
    d.rectangle([9, 23, 11, 33], fill=fur_dark, outline=outline)
    d.rectangle([13, 24, 15, 34], fill=fur_body, outline=outline)
    d.rectangle([21, 23, 23, 33], fill=fur_dark, outline=outline)
    d.rectangle([24, 24, 26, 34], fill=fur_body, outline=outline)
    
    # Hoofs
    d.point((10, 34), fill=hoof_color)
    d.point((14, 35), fill=hoof_color)
    d.point((22, 34), fill=hoof_color)
    d.point((25, 35), fill=hoof_color)
    
    # Tail
    d.ellipse([6, 14, 9, 18], fill=fur_belly, outline=outline)
    
    img.save("e:/Planetki/Assets/nature_clean/animal_deer.png")
    print("Deer sprite saved.")

def create_carcass():
    # 24x24 canvas
    img = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    meat_color = (175, 55, 50, 255)
    fat_color = (235, 210, 200, 255)
    hide_color = (130, 85, 50, 255)
    rope_color = (210, 180, 110, 255)
    outline = (70, 30, 25, 255)
    
    # Bundled carcass wrapped with hide & rope
    d.ellipse([4, 6, 20, 18], fill=hide_color, outline=outline)
    d.ellipse([7, 9, 17, 15], fill=meat_color)
    d.point((9, 11), fill=fat_color)
    d.point((13, 12), fill=fat_color)
    
    # Twine / ropes
    d.line([(8, 6), (8, 18)], fill=rope_color, width=1)
    d.line([(15, 6), (15, 18)], fill=rope_color, width=1)
    
    img.save("e:/Planetki/Assets/nature_clean/carcass.png")
    print("Carcass sprite saved.")

create_hare()
create_deer()
create_carcass()
