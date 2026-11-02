#!/usr/bin/env python3
"""Generate the HackerTube tvOS app icon (layered) and top-shelf images into Assets.xcassets (original art)."""
import json
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XC = os.path.join(ROOT, "Assets.xcassets")
BRAND = os.path.join(XC, "App Icon & Top Shelf Image.brandassets")
INFO = {"author": "xcode", "version": 1}
ORANGE, DARK = (255, 102, 0), (22, 22, 26)


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def font(size):
    for p in ["/System/Library/Fonts/Supplemental/Arial Black.ttf", "/System/Library/Fonts/Supplemental/Arial Bold.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def background(w, h):
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):  # warm orange gradient
        t = y / h
        d.line([(0, y), (w, y)], fill=(255, int(122 - 40 * t), int(20 - 20 * t), 255))
    return img


def screen(w, h, frac=0.62):
    """A dark rounded TV screen with an orange 'Y' and a white play triangle."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    sh = int(h * frac)
    sw = int(sh * 16 / 10)
    x0, y0 = (w - sw) // 2, (h - sh) // 2
    d.rounded_rectangle([x0, y0, x0 + sw, y0 + sh], radius=sh // 7, fill=DARK, outline=(255, 255, 255), width=max(2, sh // 40))
    f = font(int(sh * 0.62))
    d.text((x0 + sw * 0.34, y0 + sh * 0.5), "Y", font=f, fill=ORANGE, anchor="mm")
    tx, ty, ts = x0 + sw * 0.68, y0 + sh * 0.5, sh * 0.24
    d.polygon([(tx - ts * 0.6, ty - ts), (tx - ts * 0.6, ty + ts), (tx + ts, ty)], fill=(255, 255, 255))
    return img


def imagestack(name, size, scales):
    stack = os.path.join(BRAND, f"{name}.imagestack")
    layers = [("Front", screen), ("Back", background)]
    write_json(os.path.join(stack, "Contents.json"), {"info": INFO, "layers": [{"filename": f"{n}.imagestacklayer"} for n, _ in layers]})
    for lname, make in layers:
        layer = os.path.join(stack, f"{lname}.imagestacklayer")
        write_json(os.path.join(layer, "Contents.json"), {"info": INFO})
        images = []
        for s in scales:
            fn = f"{lname.lower()}@{s}x.png"
            os.makedirs(os.path.join(layer, "Content.imageset"), exist_ok=True)
            make(size[0] * s, size[1] * s).save(os.path.join(layer, "Content.imageset", fn))
            images.append({"idiom": "tv", "filename": fn, "scale": f"{s}x"})
        write_json(os.path.join(layer, "Content.imageset", "Contents.json"), {"info": INFO, "images": images})


def topshelf(name, size):
    iset = os.path.join(BRAND, f"{name}.imageset")
    images = []
    for s in (1, 2):
        w, h = size[0] * s, size[1] * s
        img = Image.new("RGBA", (w, h), DARK + (255,))
        img.alpha_composite(screen(h, h, 0.5), (int(w * 0.06), 0))
        d = ImageDraw.Draw(img)
        x = int(w * 0.06) + h
        d.text((x, int(h * 0.36)), "Hacker", font=font(int(h * 0.16)), fill=(255, 255, 255))
        d.text((x + d.textlength("Hacker", font=font(int(h * 0.16))), int(h * 0.36)), "Tube", font=font(int(h * 0.16)), fill=ORANGE)
        d.text((x, int(h * 0.60)), "Videos recommended on Hacker News", font=font(int(h * 0.055)), fill=(190, 190, 195))
        fn = f"{name.replace(' ', '_').lower()}@{s}x.png"
        os.makedirs(iset, exist_ok=True)
        img.convert("RGB").save(os.path.join(iset, fn))
        images.append({"idiom": "tv", "filename": fn, "scale": f"{s}x"})
    write_json(os.path.join(iset, "Contents.json"), {"info": INFO, "images": images})


def main():
    write_json(os.path.join(XC, "Contents.json"), {"info": INFO})
    imagestack("App Icon", (400, 240), (1, 2))
    imagestack("App Icon - App Store", (1280, 768), (1,))
    topshelf("Top Shelf Image", (1920, 720))
    topshelf("Top Shelf Image Wide", (2320, 720))
    write_json(os.path.join(BRAND, "Contents.json"), {"info": INFO, "assets": [
        {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
        {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
        {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
        {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
    ]})
    icon = background(800, 480)
    icon.alpha_composite(screen(800, 480))
    icon.convert("RGB").save(os.path.join(ROOT, "preview", "icon.png"))
    print("art written to", XC)


if __name__ == "__main__":
    main()
