import os
import math
from PIL import Image, ImageDraw, ImageFilter

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

def generate_masks(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    size = 64
    
    # 1. Edge masks (North, South, East, West)
    # North Edge: Top 24 pixels transition smoothly
    edge_n = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(size):
        for x in range(size):
            # organic wobble
            wobble = 3.0 * math.sin(x * 0.3) + 2.0 * math.cos(x * 0.7)
            dist = (y + wobble) / 24.0
            if dist <= 0:
                alpha = 255
            elif dist >= 1.0:
                alpha = 0
            else:
                alpha = int(255 * (1.0 - (3.0 * dist**2 - 2.0 * dist**3)))
            edge_n.putpixel((x, y), (255, 255, 255, alpha))
    edge_n.save(f"{out_dir}/edge_n.png")
    
    # South Edge (rotate 180 or flip)
    edge_s = edge_n.transpose(Image.FLIP_TOP_BOTTOM)
    edge_s.save(f"{out_dir}/edge_s.png")
    
    # West Edge (rotate 270)
    edge_w = edge_n.transpose(Image.ROTATE_90)
    edge_w.save(f"{out_dir}/edge_w.png")
    
    # East Edge (rotate 90)
    edge_e = edge_n.transpose(Image.ROTATE_270)
    edge_e.save(f"{out_dir}/edge_e.png")
    
    # 2. Outer Corner Masks (Corner is filled)
    # Outer NW: Top-Left quadrant filled
    corner_outer_nw = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(size):
        for x in range(size):
            r = math.sqrt(x**2 + y**2)
            wobble = 3.0 * math.sin(math.atan2(y, max(0.1, x)) * 5.0)
            dist = (r + wobble) / 28.0
            if dist <= 0:
                alpha = 255
            elif dist >= 1.0:
                alpha = 0
            else:
                alpha = int(255 * (1.0 - (3.0 * dist**2 - 2.0 * dist**3)))
            corner_outer_nw.putpixel((x, y), (255, 255, 255, alpha))
    corner_outer_nw.save(f"{out_dir}/corner_outer_nw.png")
    
    corner_outer_ne = corner_outer_nw.transpose(Image.FLIP_LEFT_RIGHT)
    corner_outer_ne.save(f"{out_dir}/corner_outer_ne.png")
    
    corner_outer_sw = corner_outer_nw.transpose(Image.FLIP_TOP_BOTTOM)
    corner_outer_sw.save(f"{out_dir}/corner_outer_sw.png")
    
    corner_outer_se = corner_outer_ne.transpose(Image.FLIP_TOP_BOTTOM)
    corner_outer_se.save(f"{out_dir}/corner_outer_se.png")

    # 3. Inner Corner Masks (Diagonal corner cut out)
    # Inner NW: Top-Left is EMPTY, rest is FILLED
    corner_inner_nw = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(size):
        for x in range(size):
            r = math.sqrt(x**2 + y**2)
            wobble = 3.0 * math.sin(math.atan2(y, max(0.1, x)) * 5.0)
            dist = (r + wobble) / 28.0
            if dist <= 0:
                alpha = 0
            elif dist >= 1.0:
                alpha = 255
            else:
                alpha = int(255 * (3.0 * dist**2 - 2.0 * dist**3))
            corner_inner_nw.putpixel((x, y), (255, 255, 255, alpha))
    corner_inner_nw.save(f"{out_dir}/corner_inner_nw.png")

    corner_inner_ne = corner_inner_nw.transpose(Image.FLIP_LEFT_RIGHT)
    corner_inner_ne.save(f"{out_dir}/corner_inner_ne.png")

    corner_inner_sw = corner_inner_nw.transpose(Image.FLIP_TOP_BOTTOM)
    corner_inner_sw.save(f"{out_dir}/corner_inner_sw.png")

    corner_inner_se = corner_inner_ne.transpose(Image.FLIP_TOP_BOTTOM)
    corner_inner_se.save(f"{out_dir}/corner_inner_se.png")

def generate_rivers(water_tex, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    size = 64
    half = size / 2.0
    river_w = 18.0
    half_rw = river_w / 2.0
    
    # Helper to mask water_tex with an alpha mask
    def apply_mask(mask_img):
        result = water_tex.copy()
        # Add slight water color tinting and blending
        for y in range(size):
            for x in range(size):
                p = water_tex.getpixel((x, y))
                m = mask_img.getpixel((x, y))
                result.putpixel((x, y), (p[0], p[1], p[2], m[3]))
        return result

    # 1. Horizontal River (W-E)
    mask_h = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(size):
        dist_y = abs(y - half)
        wobble = 2.0 * math.sin(y * 0.2)
        eff_dist = (dist_y + wobble)
        if eff_dist <= half_rw:
            alpha = 255
        elif eff_dist >= half_rw + 6.0:
            alpha = 0
        else:
            alpha = int(255 * (1.0 - (eff_dist - half_rw) / 6.0))
        for x in range(size):
            mask_h.putpixel((x, y), (255, 255, 255, alpha))
    apply_mask(mask_h).save(f"{out_dir}/river_h.png")

    # 2. Vertical River (N-S)
    mask_v = mask_h.transpose(Image.ROTATE_90)
    apply_mask(mask_v).save(f"{out_dir}/river_v.png")

    # 3. Turns (NW, NE, SW, SE)
    mask_turn_se = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(size):
        for x in range(size):
            r = math.sqrt((size - x)**2 + (size - y)**2)
            dist = abs(r - half)
            if dist <= half_rw:
                alpha = 255
            elif dist >= half_rw + 6.0:
                alpha = 0
            else:
                alpha = int(255 * (1.0 - (dist - half_rw) / 6.0))
            if x >= half or y >= half:
                mask_turn_se.putpixel((x, y), (255, 255, 255, alpha))
            else:
                mask_turn_se.putpixel((x, y), (0, 0, 0, 0))
    apply_mask(mask_turn_se).save(f"{out_dir}/river_turn_se.png")
    
    mask_turn_sw = mask_turn_se.transpose(Image.FLIP_LEFT_RIGHT)
    apply_mask(mask_turn_sw).save(f"{out_dir}/river_turn_sw.png")
    
    mask_turn_ne = mask_turn_se.transpose(Image.FLIP_TOP_BOTTOM)
    apply_mask(mask_turn_ne).save(f"{out_dir}/river_turn_ne.png")
    
    mask_turn_nw = mask_turn_sw.transpose(Image.FLIP_TOP_BOTTOM)
    apply_mask(mask_turn_nw).save(f"{out_dir}/river_turn_nw.png")

    # 4. Cross & T-Junctions
    mask_cross = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(size):
        for x in range(size):
            a_h = mask_h.getpixel((x, y))[3]
            a_v = mask_v.getpixel((x, y))[3]
            a = max(a_h, a_v)
            mask_cross.putpixel((x, y), (255, 255, 255, a))
    apply_mask(mask_cross).save(f"{out_dir}/river_cross.png")

    # T-junctions
    mask_t_s = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(size):
        for x in range(size):
            a_h = mask_h.getpixel((x, y))[3]
            a_v = mask_v.getpixel((x, y))[3] if y >= half else 0
            mask_t_s.putpixel((x, y), (255, 255, 255, max(a_h, a_v)))
    apply_mask(mask_t_s).save(f"{out_dir}/river_t_s.png")

    mask_t_n = mask_t_s.transpose(Image.FLIP_TOP_BOTTOM)
    apply_mask(mask_t_n).save(f"{out_dir}/river_t_n.png")

    mask_t_e = mask_t_s.transpose(Image.ROTATE_90)
    apply_mask(mask_t_e).save(f"{out_dir}/river_t_e.png")

    mask_t_w = mask_t_s.transpose(Image.ROTATE_270)
    apply_mask(mask_t_w).save(f"{out_dir}/river_t_w.png")

def main():
    atlas_path = r"C:\Users\Ham_h\.gemini\antigravity-ide\brain\14f72143-5c6c-4f6c-9abc-8bd249096145\.user_uploaded\media_1789587622552.jpg"
    atlas = Image.open(atlas_path).convert("RGBA")
    
    base_out = "Assets/terrain_atlas"
    generate_masks(f"{base_out}/masks")
    
    # River water texture from row 6 (y: 384..448)
    water_tex = make_seamless(atlas.crop((64, 384, 128, 448)))
    generate_rivers(water_tex, f"{base_out}/rivers")
    
    print("Terrain system assets (seamless base, transition masks, river network) generated successfully!")

if __name__ == "__main__":
    main()
