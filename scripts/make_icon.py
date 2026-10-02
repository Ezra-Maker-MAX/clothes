#!/usr/bin/env python3
"""衣念 App 图标生成器 —— 莫兰迪紫底 + 白「念」字印章环 + 蜜桃心点缀"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

S = 1024  # 主画布
CX = CY = S // 2
RING_R = 352          # 印章环半径
FONT = '/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc'

# ---- 1. 渐变底（莫兰迪紫：上浅下深）----
grad = Image.new('RGBA', (S, S))
top, bot = (142, 124, 187), (103, 88, 146)   # #8E7CBB -> #675892
px = grad.load()
for y in range(S):
    t = y / (S - 1)
    c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,)
    for x in range(S):
        px[x, y] = c

# 呼吸感高光：左上柔光
hl = Image.new('RGBA', (S, S), (0, 0, 0, 0))
ImageDraw.Draw(hl).ellipse([-S * 0.30, -S * 0.38, S * 0.72, S * 0.44], fill=(255, 255, 255, 40))
hl = hl.filter(ImageFilter.GaussianBlur(130))
grad = Image.alpha_composite(grad, hl)

# 圆角蒙版
mask = Image.new('L', (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=228, fill=255)
img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
img.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(img)

# ---- 2. 印章环（白色细环，微透明呼吸感）----
d.ellipse([CX - RING_R, CY - RING_R, CX + RING_R, CY + RING_R],
          outline=(255, 255, 255, 225), width=18)

# ---- 3. 「念」字（Noto Serif CJK Bold，视觉居中微调）----
font = ImageFont.truetype(FONT, 432)
d.text((CX, CY - 10), '念', font=font, fill=(255, 255, 255, 255), anchor='mm')

# ---- 4. 蜜桃心（落在印章环右下 45°，呼应"宠她"）----
def heart(draw, cx, cy, w, fill):
    r = w / 4.0
    ytop = cy - w * 0.10
    draw.ellipse([cx - w / 2, ytop - r, cx, ytop + r], fill=fill)
    draw.ellipse([cx, ytop - r, cx + w / 2, ytop + r], fill=fill)
    draw.polygon([(cx - w / 2, ytop + r * 0.35), (cx + w / 2, ytop + r * 0.35),
                  (cx, cy + w * 0.52)], fill=fill)

hx = CX + int(RING_R * 0.70)
hy = CY + int(RING_R * 0.70)
# 心底下垫片：直接采样合成渐变图上该位置的像素色，与背景无缝
_pad = grad.getpixel((hx, hy))
d.ellipse([hx - 78, hy - 78, hx + 78, hy + 78], fill=_pad)
heart(d, hx, hy, 128, (244, 193, 173, 255))     # #F4C1AD 蜜桃

# ---- 5. 输出主视觉 ----
out = '/workspace/yinian-icon-master.png'
img.save(out)
print('master ->', out)

# ---- 6. 批量导出各尺寸 ----
def save(size, path, rounded=True, scale=1.0):
    """从主视觉缩放导出；scale<1 用于 maskable 安全区（内容缩小、底满铺）"""
    if scale == 1.0:
        src = img
    else:
        # 内容整体缩放后居中贴回满铺渐变底
        art = img.resize((int(S * scale), int(S * scale)), Image.LANCZOS)
        base = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        base.paste(grad, (0, 0))
        off = (S - art.width) // 2
        base.alpha_composite(art, (off, off))
        src = base
    im = src.resize((size, size), Image.LANCZOS)
    if not rounded:
        im = im.resize((size, size), Image.LANCZOS)  # maskable：不裁圆角
    im.save(path)
    print(size, '->', path)

A = '/workspace/dapei-app/app/android/app/src/main/res'
W = '/workspace/dapei-app/app/web'
P = '/workspace/dapei-app/public'

for dpi, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    save(size, f'{A}/mipmap-{dpi}/ic_launcher.png')
save(192, f'{W}/icons/Icon-192.png')
save(512, f'{W}/icons/Icon-512.png')
save(192, f'{W}/icons/Icon-maskable-192.png', rounded=False, scale=0.78)
save(512, f'{W}/icons/Icon-maskable-512.png', rounded=False, scale=0.78)
save(64, f'{W}/favicon.png')
# public 同步 web 图标
import shutil
shutil.copy(f'{W}/icons/Icon-192.png', f'{P}/icons/Icon-192.png')
shutil.copy(f'{W}/icons/Icon-512.png', f'{P}/icons/Icon-512.png')
shutil.copy(f'{W}/icons/Icon-maskable-192.png', f'{P}/icons/Icon-maskable-192.png')
shutil.copy(f'{W}/icons/Icon-maskable-512.png', f'{P}/icons/Icon-maskable-512.png')
shutil.copy(f'{W}/favicon.png', f'{P}/favicon.png')
print('全部导出完成')
