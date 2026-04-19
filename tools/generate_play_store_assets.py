from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'marketing' / 'google-play-assets'
LOGO_PATH = ROOT / 'logos' / 'logo4_icon_square.png'
MARK_PATH = ROOT / 'logos' / 'logo_mark_clean.png'

COLORS = {
    'bg_top': (233, 246, 237),
    'bg_bottom': (217, 237, 225),
    'surface': (246, 251, 248),
    'surface_2': (236, 246, 239),
    'primary': (34, 143, 89),
    'primary_dark': (24, 108, 70),
    'text': (22, 42, 31),
    'muted': (94, 114, 103),
    'chip_bg': (225, 241, 230),
    'chip_border': (181, 214, 194),
    'card_bg': (253, 255, 254),
    'danger': (201, 45, 45),
}


def ensure_dirs() -> None:
    for folder in [
        OUT / 'app-icon',
        OUT / 'feature-graphic',
        OUT / 'phone',
        OUT / 'tablet-7in',
        OUT / 'chromebook',
        OUT / 'android-xr',
    ]:
        folder.mkdir(parents=True, exist_ok=True)


def get_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    win = Path('C:/Windows/Fonts')
    candidates = [
        win / ('segoeuib.ttf' if bold else 'segoeui.ttf'),
        win / ('arialbd.ttf' if bold else 'arial.ttf'),
    ]
    for c in candidates:
        if c.exists():
            return ImageFont.truetype(str(c), size=size)
    return ImageFont.load_default()


def vertical_gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    w, h = size
    base = Image.new('RGB', (w, h), top)
    dr = ImageDraw.Draw(base)
    for y in range(h):
        t = y / max(h - 1, 1)
        col = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        dr.line([(0, y), (w, y)], fill=col)
    return base


def draw_logo_mark(canvas: Image.Image, x: int, y: int, size: int) -> None:
    logo = Image.open(MARK_PATH).convert('RGBA')
    logo = logo.resize((size, size), Image.LANCZOS)
    canvas.alpha_composite(logo, (x, y))


def draw_header(draw: ImageDraw.ImageDraw, canvas: Image.Image, x: int, y: int, w: int, h: int) -> None:
    r = int(h * 0.35)
    draw.rounded_rectangle((x, y, x + w, y + h), radius=r, fill=COLORS['surface'])
    icon_size = int(h * 0.62)
    draw_logo_mark(canvas, x + int(h * 0.2), y + int((h - icon_size) / 2), icon_size)
    title_font = get_font(int(h * 0.36), bold=True)
    subtitle_font = get_font(int(h * 0.22), bold=False)
    tx = x + int(h * 0.2) + icon_size + int(h * 0.18)
    draw.text((tx, y + int(h * 0.16)), 'DZMarket', font=title_font, fill=COLORS['text'])
    draw.text((tx, y + int(h * 0.55)), 'Achetez, vendez, expediez', font=subtitle_font, fill=COLORS['muted'])


def draw_search(draw: ImageDraw.ImageDraw, x: int, y: int, w: int, h: int, text: str) -> None:
    draw.rounded_rectangle((x, y, x + w, y + h), radius=int(h * 0.45), fill=COLORS['surface'], outline=COLORS['chip_border'], width=2)
    font = get_font(int(h * 0.34))
    draw.text((x + int(h * 0.5), y + int(h * 0.27)), text, font=font, fill=COLORS['muted'])


def draw_chips(draw: ImageDraw.ImageDraw, x: int, y: int, labels: list[str], chip_h: int, gap: int) -> None:
    cx = x
    font = get_font(int(chip_h * 0.4))
    for label in labels:
        tw = int(draw.textlength(label, font=font))
        cw = tw + int(chip_h * 1.2)
        draw.rounded_rectangle((cx, y, cx + cw, y + chip_h), radius=int(chip_h * 0.45), fill=COLORS['chip_bg'], outline=COLORS['chip_border'], width=2)
        draw.text((cx + int(chip_h * 0.55), y + int(chip_h * 0.28)), label, font=font, fill=COLORS['primary_dark'])
        cx += cw + gap


def draw_listing_card(draw: ImageDraw.ImageDraw, x: int, y: int, w: int, h: int, title: str, price: str, subtitle: str) -> None:
    radius = int(h * 0.06)
    draw.rounded_rectangle((x, y, x + w, y + h), radius=radius, fill=COLORS['card_bg'], outline=COLORS['chip_border'], width=2)
    img_h = int(h * 0.58)
    draw.rounded_rectangle((x + 8, y + 8, x + w - 8, y + img_h), radius=int(radius * 0.8), fill=(224, 232, 227))
    pf = get_font(int(h * 0.08), bold=True)
    tf = get_font(int(h * 0.09), bold=True)
    sf = get_font(int(h * 0.07))
    draw.text((x + int(w * 0.06), y + img_h + int(h * 0.04)), title, font=tf, fill=COLORS['text'])
    draw.text((x + int(w * 0.06), y + img_h + int(h * 0.17)), subtitle, font=sf, fill=COLORS['muted'])
    pbox_w = int(w * 0.36)
    pbox_h = int(h * 0.14)
    px = x + w - pbox_w - int(w * 0.05)
    py = y + int(h * 0.04)
    draw.rounded_rectangle((px, py, px + pbox_w, py + pbox_h), radius=int(pbox_h * 0.45), fill=COLORS['surface'])
    draw.text((px + int(pbox_h * 0.4), py + int(pbox_h * 0.24)), price, font=pf, fill=COLORS['text'])


def draw_bottom_nav(draw: ImageDraw.ImageDraw, x: int, y: int, w: int, h: int, tabs: list[str], active: int) -> None:
    draw.rectangle((x, y, x + w, y + h), fill=COLORS['surface'])
    font = get_font(int(h * 0.22), bold=True)
    tw = w // len(tabs)
    for i, tab in enumerate(tabs):
        tx = x + i * tw
        if i == active:
            draw.rounded_rectangle((tx + int(tw * 0.15), y + int(h * 0.15), tx + int(tw * 0.85), y + int(h * 0.85)), radius=int(h * 0.3), fill=COLORS['chip_bg'])
        txt_w = int(draw.textlength(tab, font=font))
        draw.text((tx + (tw - txt_w) // 2, y + int(h * 0.44)), tab, font=font, fill=COLORS['text'])


def render_screen(size: tuple[int, int], mode: str, out_file: Path) -> None:
    w, h = size
    base = vertical_gradient(size, COLORS['bg_top'], COLORS['bg_bottom']).convert('RGBA')
    dr = ImageDraw.Draw(base)

    pad = int(min(w, h) * 0.04)
    header_h = int(h * 0.09)

    draw_header(dr, base, pad, pad, w - 2 * pad, header_h)

    cy = pad + header_h + int(h * 0.02)

    if mode in {'browse', 'home'}:
        search_h = int(h * 0.06)
        draw_search(dr, pad, cy, w - 2 * pad, search_h, 'Rechercher des articles...')
        cy += search_h + int(h * 0.02)
        draw_chips(dr, pad, cy, ['Filtres', 'Categories', 'Prix', 'Livraison'], int(h * 0.045), int(w * 0.015))
        cy += int(h * 0.07)
        cols = 2 if w / h < 1 else 3
        gap = int(w * 0.02)
        card_w = (w - 2 * pad - (cols - 1) * gap) // cols
        card_h = int(h * 0.31)
        for i in range(cols):
            x = pad + i * (card_w + gap)
            draw_listing_card(dr, x, cy, card_w, card_h, ['Machine', 'Telephone', 'Chaussures'][i % 3], ['6 000 DA', '30 000 DA', '1 200 DA'][i % 3], ['El Oued', 'M\'Sila', 'Alger'][i % 3])
        if h > w:
            nav_h = int(h * 0.11)
            draw_bottom_nav(dr, 0, h - nav_h, w, nav_h, ['Parcourir', 'Chat', 'Profil'], 0)

    elif mode == 'profile':
        section_y = cy
        title_f = get_font(int(h * 0.04), bold=True)
        dr.text((pad, section_y), 'Mon profil', font=title_f, fill=COLORS['text'])
        section_y += int(h * 0.05)
        row_h = int(h * 0.08)
        labels = ['Notifications', 'Mes ventes', 'Mes annonces', 'Tableau de bord', 'Parametres transporteurs']
        rf = get_font(int(row_h * 0.33))
        sf = get_font(int(row_h * 0.24))
        for idx, lb in enumerate(labels):
            y = section_y + idx * (row_h + int(h * 0.01))
            dr.rounded_rectangle((pad, y, w - pad, y + row_h), radius=int(row_h * 0.25), fill=COLORS['surface'])
            dr.text((pad + int(row_h * 0.45), y + int(row_h * 0.25)), lb, font=rf, fill=COLORS['text'])
            dr.text((w - pad - int(row_h * 0.8), y + int(row_h * 0.25)), '>', font=rf, fill=COLORS['muted'])
            if idx == 0:
                dr.text((pad + int(row_h * 0.45), y + int(row_h * 0.56)), '4 non lues', font=sf, fill=COLORS['muted'])
        if h > w:
            nav_h = int(h * 0.11)
            draw_bottom_nav(dr, 0, h - nav_h, w, nav_h, ['Parcourir', 'Chat', 'Profil'], 2)

    elif mode == 'chat':
        title_f = get_font(int(h * 0.04), bold=True)
        dr.text((pad, cy), 'Messages', font=title_f, fill=COLORS['text'])
        cy += int(h * 0.06)
        draw_search(dr, pad, cy, w - 2 * pad, int(h * 0.06), 'Rechercher une conversation...')
        cy += int(h * 0.08)
        row_h = int(h * 0.1)
        rf = get_font(int(row_h * 0.3), bold=True)
        sf = get_font(int(row_h * 0.24))
        for i in range(4):
            y = cy + i * (row_h + int(h * 0.012))
            dr.rounded_rectangle((pad, y, w - pad, y + row_h), radius=int(row_h * 0.2), fill=COLORS['surface'])
            dr.ellipse((pad + int(row_h * 0.2), y + int(row_h * 0.2), pad + int(row_h * 0.8), y + int(row_h * 0.8)), fill=COLORS['chip_bg'])
            dr.text((pad + int(row_h * 1.0), y + int(row_h * 0.22)), f'Conversation {i+1}', font=rf, fill=COLORS['text'])
            dr.text((pad + int(row_h * 1.0), y + int(row_h * 0.56)), 'Nouveau message', font=sf, fill=COLORS['muted'])
        if h > w:
            nav_h = int(h * 0.11)
            draw_bottom_nav(dr, 0, h - nav_h, w, nav_h, ['Parcourir', 'Chat', 'Profil'], 1)

    elif mode == 'sell':
        title_f = get_font(int(h * 0.04), bold=True)
        dr.text((pad, cy), 'Nouvelle annonce', font=title_f, fill=COLORS['text'])
        cy += int(h * 0.06)
        row_h = int(h * 0.07)
        fields = ['Titre', 'Description', 'Prix', 'Stock', 'Wilaya', 'Commune']
        ff = get_font(int(row_h * 0.35))
        for i, f in enumerate(fields):
            y = cy + i * (row_h + int(h * 0.012))
            dr.rounded_rectangle((pad, y, w - pad, y + row_h), radius=int(row_h * 0.25), fill=COLORS['surface'], outline=COLORS['chip_border'], width=2)
            dr.text((pad + int(row_h * 0.35), y + int(row_h * 0.28)), f, font=ff, fill=COLORS['muted'])
        btn_h = int(h * 0.08)
        by = cy + len(fields) * (row_h + int(h * 0.012)) + int(h * 0.03)
        dr.rounded_rectangle((w - pad - int(w * 0.32), by, w - pad, by + btn_h), radius=int(btn_h * 0.45), fill=COLORS['primary'])
        bf = get_font(int(btn_h * 0.36), bold=True)
        txt = 'Publier'
        tw = int(dr.textlength(txt, font=bf))
        dr.text((w - pad - int(w * 0.16) - tw // 2, by + int(btn_h * 0.28)), txt, font=bf, fill=(255, 255, 255))

    elif mode == 'xr':
        # Wide format hero-like app preview
        title_f = get_font(int(h * 0.07), bold=True)
        sub_f = get_font(int(h * 0.035))
        dr.text((pad, cy), 'DZMarket', font=title_f, fill=COLORS['text'])
        dr.text((pad, cy + int(h * 0.09)), 'Marketplace moderne: acheter, vendre, expedier', font=sub_f, fill=COLORS['muted'])
        cy += int(h * 0.18)
        panel_w = (w - 2 * pad - int(w * 0.03)) // 2
        panel_h = int(h * 0.55)
        for i in range(2):
            x = pad + i * (panel_w + int(w * 0.03))
            dr.rounded_rectangle((x, cy, x + panel_w, cy + panel_h), radius=int(panel_h * 0.07), fill=COLORS['surface'])
            draw_listing_card(dr, x + int(panel_w * 0.04), cy + int(panel_h * 0.08), int(panel_w * 0.42), int(panel_h * 0.76), 'Produit', '2 500 DA', 'Livraison')
            draw_listing_card(dr, x + int(panel_w * 0.52), cy + int(panel_h * 0.08), int(panel_w * 0.42), int(panel_h * 0.76), 'Produit', '8 000 DA', 'Retrait')

    # soft vignette
    vignette = Image.new('L', (w, h), 255)
    vd = ImageDraw.Draw(vignette)
    margin = int(min(w, h) * 0.02)
    vd.rectangle((margin, margin, w - margin, h - margin), fill=220)
    vignette = vignette.filter(ImageFilter.GaussianBlur(radius=int(min(w, h) * 0.03)))
    base.putalpha(vignette)

    out_file.parent.mkdir(parents=True, exist_ok=True)
    base.convert('RGB').save(out_file, format='PNG', optimize=True)


def make_app_icon() -> None:
    size = 512
    img = vertical_gradient((size, size), (228, 244, 234), (207, 233, 217)).convert('RGBA')
    dr = ImageDraw.Draw(img)
    pad = 44
    dr.rounded_rectangle((pad, pad, size - pad, size - pad), radius=96, fill=(240, 251, 245), outline=(170, 214, 190), width=3)
    draw_logo_mark(img, 112, 88, 288)
    img.convert('RGB').save(OUT / 'app-icon' / 'dzmarket_app_icon_512.png', optimize=True)


def make_feature_graphic() -> None:
    w, h = 1024, 500
    img = vertical_gradient((w, h), (224, 242, 230), (203, 230, 213)).convert('RGBA')
    dr = ImageDraw.Draw(img)

    dr.rounded_rectangle((40, 40, 984, 460), radius=48, fill=(237, 248, 241))
    draw_logo_mark(img, 90, 110, 280)

    title = get_font(74, bold=True)
    sub = get_font(34)
    dr.text((410, 140), 'DZMarket', font=title, fill=COLORS['text'])
    dr.text((410, 235), 'Achetez, vendez, expediez', font=sub, fill=COLORS['muted'])
    chipf = get_font(24, bold=True)
    chip_labels = ['Marketplace', 'Livraison integree', 'FR / AR']
    cx = 410
    cy = 305
    for c in chip_labels:
        tw = int(dr.textlength(c, font=chipf))
        cw = tw + 36
        dr.rounded_rectangle((cx, cy, cx + cw, cy + 46), radius=20, fill=COLORS['chip_bg'], outline=COLORS['chip_border'], width=2)
        dr.text((cx + 18, cy + 12), c, font=chipf, fill=COLORS['primary_dark'])
        cx += cw + 14

    img.convert('RGB').save(OUT / 'feature-graphic' / 'dzmarket_feature_graphic_1024x500.png', optimize=True)


def write_readme() -> None:
    txt = '''# Google Play Store Assets (Generated)

Generated folder for Play Console uploads.

## Files
- `app-icon/dzmarket_app_icon_512.png` (512x512)
- `feature-graphic/dzmarket_feature_graphic_1024x500.png` (1024x500)
- `phone/` (1080x1920)
- `tablet-7in/` (1920x1200)
- `chromebook/` (1920x1080)
- `android-xr/` (3840x2160)

## Notes
- Images are generated branded mockups ready for Play listing sections.
- If Play requests in-app capture realism, replace screenshots with real captures from production build while keeping same resolutions.
'''
    (OUT / 'README.md').write_text(txt, encoding='utf-8')


def main() -> None:
    ensure_dirs()
    make_app_icon()
    make_feature_graphic()

    # Phone screenshots
    render_screen((1080, 1920), 'browse', OUT / 'phone' / 'phone_01_browse_1080x1920.png')
    render_screen((1080, 1920), 'chat', OUT / 'phone' / 'phone_02_chat_1080x1920.png')
    render_screen((1080, 1920), 'profile', OUT / 'phone' / 'phone_03_profile_1080x1920.png')
    render_screen((1080, 1920), 'sell', OUT / 'phone' / 'phone_04_sell_1080x1920.png')

    # 7-inch tablet (landscape)
    render_screen((1920, 1200), 'browse', OUT / 'tablet-7in' / 'tablet7_01_browse_1920x1200.png')
    render_screen((1920, 1200), 'profile', OUT / 'tablet-7in' / 'tablet7_02_profile_1920x1200.png')
    render_screen((1920, 1200), 'sell', OUT / 'tablet-7in' / 'tablet7_03_sell_1920x1200.png')

    # Chromebook
    render_screen((1920, 1080), 'browse', OUT / 'chromebook' / 'chromebook_01_browse_1920x1080.png')
    render_screen((1920, 1080), 'chat', OUT / 'chromebook' / 'chromebook_02_chat_1920x1080.png')
    render_screen((1920, 1080), 'profile', OUT / 'chromebook' / 'chromebook_03_profile_1920x1080.png')

    # Android XR (wide)
    render_screen((3840, 2160), 'xr', OUT / 'android-xr' / 'android_xr_01_3840x2160.png')
    render_screen((3840, 2160), 'browse', OUT / 'android-xr' / 'android_xr_02_browse_3840x2160.png')

    write_readme()
    print(f'Assets generated in: {OUT}')


if __name__ == '__main__':
    main()
