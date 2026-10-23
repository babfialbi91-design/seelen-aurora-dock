"""Aurora monochrome wallpaper set - calm, minimal, 4K.

Every image is a study of one light form on a matte field, kept inside a
tight tonal envelope (nothing clips, nothing reads as pure black). Rendered
analytically with numpy at 3840x2160, finished with a photographic curve,
scale-safe film grain and a fine dither.

Usage: python scripts/make-wallpapers-v3.py [--out DIR] [--only 05,09]
"""

from __future__ import annotations

import argparse
import math
import os
import time

import numpy as np
from PIL import Image

W, H = 3840, 2160
FLOOR = 0.092          # deepest tone in the frame (~23/255)
TAU = math.pi * 2.0

XS = (np.arange(W, dtype=np.float32) + 0.5)[None, :]
YS = (np.arange(H, dtype=np.float32) + 0.5)[:, None]
XN = XS / W
YN = YS / H


# --------------------------------------------------------------------------
# geometry / light helpers
# --------------------------------------------------------------------------
def sstep(a: float, b: float, t):
    u = np.clip((t - a) / (b - a), 0.0, 1.0)
    return u * u * (3.0 - 2.0 * u)


def gauss2(cx, cy, sx, sy=None, rot=0.0):
    """Gaussian light, peak 1.0, radii in pixels."""
    sy = sx if sy is None else sy
    if rot:
        c, s = math.cos(rot), math.sin(rot)
        dx = (XS - cx) * c + (YS - cy) * s
        dy = -(XS - cx) * s + (YS - cy) * c
    else:
        dx = XS - cx
        dy = YS - cy
    return np.exp(-0.5 * ((dx / sx) ** 2 + (dy / sy) ** 2), dtype=np.float32)


def sd_rrect(cx, cy, w, h, r, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)
    dx = XS - cx
    dy = YS - cy
    px = np.abs(dx * c + dy * s) - (w * 0.5 - r)
    py = np.abs(-dx * s + dy * c) - (h * 0.5 - r)
    qx = np.maximum(px, 0.0)
    qy = np.maximum(py, 0.0)
    return np.sqrt(qx * qx + qy * qy) + np.minimum(np.maximum(px, py), 0.0) - r


def sd_circle(cx, cy, r):
    return np.sqrt((XS - cx) ** 2 + (YS - cy) ** 2) - r


def cov(sd, feather=1.3):
    """Anti-aliased coverage from a signed distance field in pixels."""
    return np.clip(0.5 - sd / feather, 0.0, 1.0)


def blur(a, sigma):
    """Gaussian blur via FFT with reflect padding."""
    if sigma < 0.35:
        return a
    pad = int(min(min(a.shape) - 1, max(8, sigma * 3)))
    p = np.pad(a, pad, mode="reflect")
    fy = np.fft.fftfreq(p.shape[0]).astype(np.float32)
    fx = np.fft.rfftfreq(p.shape[1]).astype(np.float32)
    g = np.exp(-2.0 * math.pi ** 2 * sigma ** 2 * (fy[:, None] ** 2 + fx[None, :] ** 2))
    out = np.fft.irfft2(np.fft.rfft2(p) * g.astype(np.float32), s=p.shape)
    return np.ascontiguousarray(out[pad:pad + a.shape[0], pad:pad + a.shape[1]], dtype=np.float32)


def blur_big(a, sigma, factor=4):
    if sigma < 10:
        return blur(a, sigma)
    h, w = a.shape
    small = np.asarray(
        Image.fromarray(a, mode="F").resize((w // factor, h // factor), Image.LANCZOS),
        dtype=np.float32,
    )
    small = blur(small, sigma / factor)
    big = Image.fromarray(small, mode="F").resize((w, h), Image.BICUBIC)
    return np.asarray(big, dtype=np.float32)


def sky(top: float, bottom: float, lights=(), vig: float = 0.18):
    ys = YN.astype(np.float32)
    field = bottom + (top - bottom) * sstep(0.0, 1.0, ys)
    field = np.broadcast_to(field, (H, W)).astype(np.float32).copy()
    for cx, cy, r, amp in lights:
        field += amp * gauss2(cx * W, cy * H, r * W)
    dx = (XN - 0.5) * (W / H)
    dy = YN - 0.5
    field *= 1.0 - vig * sstep(0.50, 1.40, np.sqrt(dx * dx + dy * dy))
    np.maximum(field, FLOOR, out=field)
    return field


def over(field, body, value):
    """Composite a form with a value field over the background."""
    return field * (1.0 - body) + body * value


def spec(field, line, core: float, bloom: float, sigma: float):
    """Add a bright hairline plus its bloom."""
    field += line * core
    if bloom:
        field += blur(line, sigma) * bloom
    return field


# --------------------------------------------------------------------------
# finishing
# --------------------------------------------------------------------------
def finish(field, seed: int) -> Image.Image:
    L = np.maximum(field, FLOOR)
    L = L / (1.0 + 0.5 * np.maximum(L - 0.82, 0.0))
    L = np.power(L, 0.98, dtype=np.float32)

    rng = np.random.default_rng(seed)
    mid = 0.30 + 0.70 * (1.0 - np.abs(2.0 * np.clip(L, 0, 1) - 1.0))
    small = rng.standard_normal((H // 2, W // 2), dtype=np.float32)
    grain = np.asarray(Image.fromarray(small, mode="F").resize((W, H), Image.BICUBIC), dtype=np.float32)
    L = L + grain * mid * 0.0065

    v = np.clip(L * 255.0 + rng.uniform(-0.5, 0.5, (H, W)).astype(np.float32), 0, 255).astype(np.uint8)
    return Image.fromarray(np.repeat(v[..., None], 3, axis=2), "RGB")


def save(img, papers_dir, name):
    prev_dir = os.path.join(papers_dir, "previews")
    os.makedirs(prev_dir, exist_ok=True)
    img.save(os.path.join(papers_dir, f"{name}.jpg"), quality=92, subsampling=0,
             optimize=True, progressive=True)
    img.resize((1600, 900), Image.LANCZOS).save(
        os.path.join(prev_dir, f"{name}.jpg"), quality=90, subsampling=0, optimize=True)
    a = np.asarray(img)
    print(f"  {name:<12} min={a.min():3d} mean={a.mean():5.1f} max={a.max():3d}", flush=True)


# --------------------------------------------------------------------------
# scenes
# --------------------------------------------------------------------------
def s01_seam() -> np.ndarray:
    """A matte wall, one crisp seam where the light changes sides."""
    f = sky(0.168, 0.132, [(0.16, 0.18, 0.62, 0.030)], 0.16)
    sx = 0.432 + 0.016 * (1.0 - YN)
    lit = sstep(0.0, 1.0, np.clip((sx - XN) / 0.34, 0.0, 1.0))
    f += lit * 0.030
    f += gauss2(sx * W, H * 0.48, 0.17 * W, 0.75 * H) * 0.028
    line = cov(np.abs(XS - sx * W) - 0.65, 1.2)
    spec(f, line, 0.26, 0.085, 30.0)
    f += gauss2(sx * W, H * 0.52, 0.55 * W, 0.28 * H) * 0.018
    return f


def s02_orb() -> np.ndarray:
    """A small orb of light held in the upper third of the frame."""
    f = sky(0.156, 0.124, [(0.66, 0.34, 0.50, 0.024)], 0.20)
    cx, cy, r = 0.645 * W, 0.355 * H, 0.118 * W

    add_bloom = blur(cov(sd_circle(cx, cy, r), 2.0), 95.0)
    f += add_bloom * 0.105
    f += gauss2(cx, cy, r * 2.6) * 0.045

    d = np.sqrt((XS - cx) ** 2 + (YS - cy) ** 2) / r
    inner = np.clip(1.0 - d * d, 0.0, 1.0) ** 0.65
    val = 0.315 + 0.245 * inner + 0.045 * gauss2(cx - r * 0.4, cy - r * 0.45, r * 1.1)
    f = over(f, cov(sd_circle(cx, cy, r), 2.4), val)

    for orb, alpha in ((1.62, 0.035), (2.28, 0.020)):
        ring = cov(np.abs(sd_circle(cx, cy, r * orb)) - 0.6, 1.1)
        f += ring * alpha

    f += gauss2(cx, cy + r * 1.85, r * 1.5, r * 0.36) * 0.030
    return f


def s03_dunes() -> np.ndarray:
    """Three matte ridges, each crest catching a thin line of light."""
    f = sky(0.170, 0.146, [(0.72, 0.14, 0.62, 0.032)], 0.18)
    layers = [
        (0.545, 0.040, 0.95, 0.35, 0.148),
        (0.638, 0.058, 1.35, 2.10, 0.130),
        (0.762, 0.050, 0.80, 4.20, 0.112),
    ]
    for base, amp, freq, phase, tone in layers:
        edge = (base + amp * np.sin(TAU * (freq * XN + phase)) + 0.075 * XN - 0.036) * H
        below = sstep(-1.8, 1.8, YS - edge)
        depth = np.clip((YS - edge) / (H * 0.42), 0.0, 1.0)
        f = f * (1.0 - below) + below * (tone - 0.020 * depth)
        crest = np.exp(-0.5 * ((YS - edge) / 1.9) ** 2).astype(np.float32)
        f += crest * 0.105 + blur(crest, 7.0) * 0.115
    f += gauss2(0.18 * W, 0.10 * H, 0.55 * W, 0.32 * H) * 0.022
    return f


def s04_lattice() -> np.ndarray:
    """A fine dot lattice dissolving into a soft pool of light."""
    f = sky(0.136, 0.120, [(0.33, 0.44, 0.50, 0.028)], 0.10)
    sp = 56.0
    mx = np.abs(((XS - sp * 0.5) % sp) - sp * 0.5)
    my = np.abs(((YS - sp * 0.5) % sp) - sp * 0.5)
    d = np.sqrt(mx * mx + my * my)
    dots = np.clip(1.0 - (d - 0.8) / 1.15, 0.0, 1.0) ** 1.6
    pool = gauss2(0.30 * W, 0.46 * H, 0.40 * W, 0.44 * H)
    f += dots * (0.030 + 0.115 * pool)
    f += pool * 0.030
    f += gauss2(0.86 * W, 0.86 * H, 0.45 * W, 0.30 * H) * 0.014
    return f


def s05_eclipse() -> np.ndarray:
    """A dark sphere with one lit limb and quiet atmospheric rings."""
    f = sky(0.166, 0.134, [(0.24, 0.18, 0.62, 0.034)], 0.20)
    cx, cy, r = 0.585 * W, 0.505 * H, 0.238 * W

    for orb, alpha in ((1.30, 0.030), (1.62, 0.018)):
        ring = cov(np.abs(sd_circle(cx, cy, r * orb)) - 0.7, 1.2)
        f += ring * alpha

    limb_c = math.radians(-42.0)
    ang = np.arctan2(YS - cy, XS - cx)
    delta = np.abs((ang - limb_c + math.pi) % TAU - math.pi)
    radial = np.exp(-0.5 * ((np.sqrt((XS - cx) ** 2 + (YS - cy) ** 2) - r * 0.975) / (r * 0.022)) ** 2)
    limb = (np.exp(-0.5 * (delta / 0.72) ** 2) * radial).astype(np.float32)

    body = cov(sd_circle(cx, cy, r), 2.2)
    shade = 0.086 + 0.030 * gauss2(cx - r * 0.55, cy - r * 0.60, r * 1.25)
    f = over(f, body, shade)

    spec(f, limb * (1.0 - body), 0.62, 0.30, 6.0)
    f += gauss2(cx + r * math.cos(limb_c) * 1.02, cy + r * math.sin(limb_c) * 1.02, r * 0.34) * 0.075
    f += gauss2(cx, cy, r * 1.9) * 0.020
    return f


def s06_monolith() -> np.ndarray:
    """A pale slab standing in still air, one edge catching the light."""
    f = sky(0.164, 0.130, [(0.16, 0.10, 0.60, 0.030), (0.88, 0.88, 0.46, 0.018)], 0.20)
    cx, cy = 0.598 * W, 0.468 * H
    w, h = 0.104 * W, 0.612 * H
    r = 0.0115 * W

    sd = sd_rrect(cx, cy, w, h, r)
    body = cov(sd, 1.6)

    f += blur_big(body, 110.0) * 0.055
    f += blur(body, 34.0) * 0.070
    f -= blur_big(cov(sd_rrect(cx + 30, cy + 38, w * 1.05, h * 1.01, r), 2.0), 70.0) * 0.045

    grad = 0.545 - 0.300 * sstep(0.02, 0.98, YN)
    grad = grad - 0.045 * sstep(0.70, 1.0, XN)
    f = over(f, body, grad.astype(np.float32))

    sheen = np.clip(1.0 - np.abs((XN - (cx / W - 0.028)) / 0.060), 0.0, 1.0) * body
    f += sheen * 0.055 * (0.45 + 0.55 * (1.0 - YN))

    left = cov(np.abs(XS - (cx - w / 2)) - 0.8, 1.2) * body
    spec(f, left, 0.30, 0.115, 12.0)
    top = cov(np.abs(YS - (cy - h / 2)) - 0.7, 1.1) * body
    f += top * 0.055
    inner = cov(np.abs(sd_rrect(cx, cy, w - 16, h - 16, r * 0.85)) - 0.7, 1.1)
    f += inner * 0.050

    f += gauss2(cx, cy + h * 0.565, w * 1.5, 30.0) * 0.060
    f += gauss2(cx - w * 0.75, cy + h * 0.05, w * 0.34, h * 0.55) * 0.030
    return f


def s07_silk() -> np.ndarray:
    """Four satin folds, lit along the crests, deep between."""
    f = sky(0.140, 0.118, [(0.60, 0.10, 0.58, 0.020)], 0.16)
    folds = [
        (0.240, 0.036, 1.10, 0.30, 0.115, 0.240),
        (0.418, 0.044, 1.45, 1.90, 0.105, 0.225),
        (0.596, 0.036, 0.95, 3.30, 0.112, 0.205),
        (0.775, 0.040, 1.30, 4.70, 0.098, 0.185),
    ]
    for y0, amp, freq, phase, thick, peak in folds:
        crest = (y0 + amp * np.sin(TAU * (freq * XN + phase)) + 0.045 * XN) * H
        depth = YS - crest
        t = np.clip(depth / (thick * H), 0.0, 1.0)
        shape = 1.0 - t * t * (3 - 2 * t)
        inside = np.where(depth >= 0.0, shape, 0.0).astype(np.float32)
        fill = inside * (peak * (1.0 - 0.62 * t))
        f += blur(fill, 5.0) * 0.92

        crestln = (np.exp(-0.5 * (depth / 1.7) ** 2) * (depth > -1.0)).astype(np.float32)
        spec(f, crestln, peak * 1.15, peak * 0.55, 5.0)

        under = np.exp(-0.5 * ((depth - thick * H * 0.80) / (H * 0.020)) ** 2).astype(np.float32)
        f -= blur(under, 18.0) * 0.055

    f += gauss2(0.12 * W, 0.05 * H, 0.42 * W, 0.22 * H) * 0.026
    return f


def s08_contour() -> np.ndarray:
    """Topographic rings under a single blade of light."""
    f = sky(0.160, 0.132, [(0.26, 0.18, 0.56, 0.024)], 0.18)
    cx, cy = 0.320 * W, 0.680 * H

    for i in range(1, 21):
        r = i * 0.0300 * W
        a = 0.105 * (1.0 - i / 23.0) ** 1.5
        ring = cov(np.abs(sd_circle(cx, cy, r) * 0.84) - 0.55, 1.0)
        fade = 0.45 + 0.55 * np.clip((YS - (cy - r)) / (2 * r), 0, 1)
        f += ring * fade * a

    ang = math.radians(-16.0)
    u = (XS - 0.5 * W) * math.cos(ang) + (YS - 0.55 * H) * math.sin(ang)
    v = -(XS - 0.5 * W) * math.sin(ang) + (YS - 0.55 * H) * math.cos(ang)
    blade = np.exp(-0.5 * (u / (H * 0.062)) ** 2).astype(np.float32)
    f += blur_big(blade, 44.0) * 0.075
    f += blur(blade, 6.0) * 0.030

    ticks = (np.abs(np.abs(u) - H * 0.011) < 0.55) & ((v % (H * 0.055)) < H * 0.022)
    f += ticks.astype(np.float32) * 0.060

    f += gauss2(cx, cy, W * 0.15, H * 0.15) * 0.040
    return f


def s09_prism() -> np.ndarray:
    """Three glass plates stacked in quiet light, crescent mark."""
    f = sky(0.158, 0.128, [(0.52, 0.44, 0.46, 0.026)], 0.18)
    f += gauss2(0.55 * W, 0.50 * H, W * 0.24) * 0.035

    plates = [
        dict(rot=42.0, size=0.330, dx=-0.056, dy=0.044, hi=0.240, lo=0.112, edge=0.55),
        dict(rot=16.0, size=0.278, dx=0.050, dy=-0.030, hi=0.275, lo=0.120, edge=0.68),
        dict(rot=0.0, size=0.226, dx=-0.006, dy=0.0, hi=0.315, lo=0.135, edge=0.80),
    ]
    for p in plates:
        side = p["size"] * W
        cx = W * (0.55 + p["dx"])
        cy = H * (0.50 + p["dy"])
        rot = math.radians(p["rot"])
        sd = sd_rrect(cx, cy, side, side, side * 0.155, rot)
        body = cov(sd, 1.6)

        f += blur_big(body, 80.0) * 0.030
        u = (XS - cx) * math.cos(rot) + (YS - cy) * math.sin(rot)
        v = -(XS - cx) * math.sin(rot) + (YS - cy) * math.cos(rot)
        gloss = np.clip(1.0 - ((u / side) * 0.85 + (v / side) * 0.55 + 0.10), 0.0, 1.0) ** 0.8
        val = (p["lo"] + (p["hi"] - p["lo"]) * gloss).astype(np.float32)
        f = over(f, body, val)

        edge = cov(np.abs(sd) - 0.62, 1.2)
        spec(f, edge, p["edge"] * 0.42, p["edge"] * 0.20, 6.0)
        inner = cov(np.abs(sd_rrect(cx, cy, side - side * 0.048, side - side * 0.048, side * 0.132, rot)) - 0.55, 1.1)
        f += inner * 0.060

    side = plates[2]["size"] * W
    cx, cy = W * 0.55, H * 0.50
    rc = 0.285 * side
    dd = 0.050 * side
    aa = math.radians(24.0)
    dx = XS - cx
    dy = YS - cy
    px = dx * math.cos(aa) + dy * math.sin(aa)
    py = -dx * math.sin(aa) + dy * math.cos(aa)
    lune = np.maximum(np.sqrt(px * px + py * py) - rc,
                      -(np.sqrt((px - dd) ** 2 + py * py) - rc * 0.995))
    mark = cov(lune, 1.2)
    dotx = dd * 0.5 + 0.150 * side
    dot = cov(np.sqrt((px - dotx) ** 2 + py * py) - 0.0205 * side, 1.2)

    shadow = blur(np.maximum(mark, dot), 6.0)
    f *= 1.0 - 0.42 * shadow
    f += mark * 0.50 + dot * 0.56
    f += gauss2(cx, cy, side * 0.32) * 0.030
    return f


def s10_beacon() -> np.ndarray:
    """A shaft of light standing in low fog."""
    f = sky(0.152, 0.126, [(0.34, 0.42, 0.36, 0.020)], 0.18)
    ang = math.radians(-13.0)
    u = (XS - 0.40 * W) * math.cos(ang) + (YS - 0.50 * H) * math.sin(ang)
    v = -(XS - 0.40 * W) * math.sin(ang) + (YS - 0.50 * H) * math.cos(ang)

    shaft = (np.exp(-0.5 * (u / (W * 0.040)) ** 2) * (0.45 + 0.55 * sstep(-0.55 * H, 0.40 * H, v))).astype(np.float32)
    f += blur_big(shaft, 70.0) * 0.105
    f += blur(shaft, 9.0) * 0.045

    core = (np.exp(-0.5 * (u / 1.4) ** 2) * np.exp(-0.5 * (v / (H * 0.40)) ** 2)).astype(np.float32)
    spec(f, core, 0.34, 0.10, 18.0)

    f += gauss2(0.43 * W, 0.60 * H, W * 0.20, H * 0.13) * 0.055
    f += gauss2(0.28 * W, 0.94 * H, W * 0.36, H * 0.09) * 0.028
    f += gauss2(0.66 * W, 0.08 * H, W * 0.30, H * 0.10) * 0.020

    rng = np.random.default_rng(9)
    dust = np.zeros((H, W), dtype=np.float32)
    idx = rng.integers(0, H * W, 800)
    np.add.at(dust.reshape(-1), idx, rng.uniform(0.20, 0.85, idx.size).astype(np.float32))
    f += blur(dust, 1.2) * 0.16
    return f


SCENES = {
    "01-seam": s01_seam,
    "02-orb": s02_orb,
    "03-dunes": s03_dunes,
    "04-lattice": s04_lattice,
    "05-eclipse": s05_eclipse,
    "06-monolith": s06_monolith,
    "07-silk": s07_silk,
    "08-contour": s08_contour,
    "09-prism": s09_prism,
    "10-beacon": s10_beacon,
}


def contact_sheet(papers_dir, names):
    tw, th, gap = 640, 360, 14
    cols = 5
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw + (cols + 1) * gap, rows * th + (rows + 1) * gap), (16, 16, 16))
    for i, name in enumerate(names):
        im = Image.open(os.path.join(papers_dir, f"{name}.jpg")).resize((tw, th), Image.LANCZOS)
        sheet.paste(im, (gap + (i % cols) * (tw + gap), gap + (i // cols) * (th + gap)))
    sheet.save(os.path.join(papers_dir, "previews", "00-set.jpg"), quality=90, optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "wallpapers"))
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    wanted = [s.strip() for s in args.only.split(",") if s.strip()]
    names = [n for n in SCENES if not wanted or n in wanted or n.split("-")[0] in wanted]

    t0 = time.time()
    for name in names:
        t = time.time()
        field = SCENES[name]()
        img = finish(field, seed=abs(hash(name)) % 99991)
        save(img, args.out, name)
        del field, img
        print(f"    {time.time() - t:5.1f}s", flush=True)
    if not wanted:
        contact_sheet(args.out, list(SCENES))
    print(f"done -> {args.out}  ({time.time() - t0:.0f}s)")


if __name__ == "__main__":
    main()
