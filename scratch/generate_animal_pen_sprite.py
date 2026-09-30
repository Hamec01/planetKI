from PIL import Image, ImageDraw

# Create an animal pen (загон для скота / оленей)
# Size 256x256 RGBA
w, h = 256, 256
img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Ground shadow
draw.ellipse([30, 110, 226, 230], fill=(0, 0, 0, 60))

# Straw / dirt bedding inside the pen
draw.polygon([(45, 160), (128, 120), (211, 160), (128, 205)], fill=(145, 115, 75, 230))
draw.polygon([(55, 160), (128, 128), (201, 160), (128, 196)], fill=(175, 142, 85, 220))
# Yellow straw patches
draw.polygon([(70, 155), (105, 138), (120, 155), (85, 170)], fill=(210, 185, 95, 230))
draw.polygon([(135, 160), (170, 145), (185, 162), (150, 178)], fill=(205, 180, 90, 230))

# Back fence (isometric posts and horizontal rails)
# Rails:
draw.line([(45, 160), (128, 120)], fill=(85, 55, 30, 255), width=6)
draw.line([(45, 148), (128, 108)], fill=(110, 72, 40, 255), width=5)
draw.line([(128, 120), (211, 160)], fill=(85, 55, 30, 255), width=6)
draw.line([(128, 108), (211, 148)], fill=(110, 72, 40, 255), width=5)

# Back posts
for px, py in [(45, 160), (86, 140), (128, 120), (169, 140), (211, 160)]:
    # vertical post
    draw.rectangle([px - 4, py - 35, px + 4, py + 2], fill=(100, 65, 35, 255), outline=(60, 38, 20, 255))
    # wooden top bevel
    draw.polygon([(px - 4, py - 35), (px, py - 40), (px + 4, py - 35)], fill=(130, 85, 48, 255))

# Wooden shelter lean-to on left corner
# Posts
draw.rectangle([45, 115, 53, 162], fill=(70, 45, 25, 255))
draw.rectangle([95, 95, 103, 142], fill=(70, 45, 25, 255))
# Straw / thatch roof
roof_pts = [(30, 120), (100, 85), (135, 102), (65, 140)]
draw.polygon(roof_pts, fill=(160, 125, 60, 255), outline=(90, 65, 30, 255))
# Thatch lines
for i in range(5):
    t = i / 4.0
    x1 = int(30 * (1 - t) + 100 * t)
    y1 = int(120 * (1 - t) + 85 * t)
    x2 = int(65 * (1 - t) + 135 * t)
    y2 = int(140 * (1 - t) + 102 * t)
    draw.line([(x1, y1), (x2, y2)], fill=(185, 148, 72, 255), width=3)

# Water / Food Trough in center-back
draw.polygon([(110, 145), (146, 145), (142, 158), (106, 158)], fill=(90, 60, 35, 255), outline=(50, 30, 18, 255))
draw.polygon([(112, 147), (144, 147), (140, 155), (108, 155)], fill=(80, 140, 170, 240)) # Water sheen

# Front fence (lower rails and posts)
# Left front rail
draw.line([(45, 160), (110, 195)], fill=(95, 62, 34, 255), width=6)
draw.line([(45, 148), (110, 183)], fill=(120, 80, 45, 255), width=5)

# Right front rail
draw.line([(146, 212), (211, 160)], fill=(95, 62, 34, 255), width=6)
draw.line([(146, 200), (211, 148)], fill=(120, 80, 45, 255), width=5)

# Front posts
for px, py in [(77, 177), (110, 195), (146, 212), (178, 186)]:
    draw.rectangle([px - 4, py - 35, px + 4, py + 4], fill=(115, 75, 42, 255), outline=(65, 40, 22, 255))
    draw.polygon([(px - 4, py - 35), (px, py - 40), (px + 4, py - 35)], fill=(145, 95, 55, 255))

# Wooden Gate in front opening (between 110, 195 and 146, 212)
# Gate frame & diagonal cross brace
draw.line([(112, 196), (144, 213)], fill=(140, 95, 55, 255), width=4)
draw.line([(112, 178), (144, 195)], fill=(155, 108, 62, 255), width=4)
draw.line([(113, 195), (143, 196)], fill=(110, 75, 40, 255), width=3) # Cross brace
# Iron latch/rope
draw.ellipse([142, 190, 147, 195], fill=(70, 70, 75, 255))

img.save("Assets/buildings/animal_pen.png")
print("Saved Assets/buildings/animal_pen.png successfully!")
