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
FLOOR = 0.100          # deepest tone in the frame (~26/255)
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
    """Add a bright hairline plus a bloom normalised to its own peak."""
    field += line * core
    if bloom:
        b = blur(line, sigma)
        m = float(b.max())
        if m > 1e-6:
            field += b * (bloom / m)
    return field


# --------------------------------------------------------------------------
# finishing
# --------------------------------------------------------------------------
def finish(field, seed: int) -> Image.Image:
    L = np.maximum(field, FLOOR)
    knee = 0.66
    hi = L > knee
    L[hi] = knee + 0.325 * np.tanh((L[hi] - knee) / 0.325)
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
    """A matte wall lit from the left; one crisp seam divides the light."""
    f = sky(0.230, 0.150, [(0.14, 0.12, 0.60, 0.030)], 0.14)
    sx = 0.438 + 0.014 * (1.0 - YN)
    lit = sstep(0.0, 1.0, np.clip((sx - XN) / 0.95, 0.0, 1.0))
    f += lit * 0.052
    f += gauss2(sx * W, H * 0.46, 0.22 * W, 0.80 * H) * 0.030
    line = cov(np.abs(XS - sx * W) - 0.60, 1.1)
    spec(f, line, 0.520, 0.105, 30.0)
    twin = cov(np.abs(XS - (sx * W - 13.0)) - 0.45, 1.0)
    spec(f, twin, 0.095, 0.030, 18.0)
    f += gauss2(0.10 * W, 0.94 * H, 0.55 * W, 0.30 * H) * 0.020
    return f


def s02_orb() -> np.ndarray:
    """A small orb of light held in the upper third of the frame."""
    f = sky(0.212, 0.158, [(0.64, 0.32, 0.52, 0.026)], 0.18)
    cx, cy, r = 0.635 * W, 0.345 * H, 0.122 * W

    body = cov(sd_circle(cx, cy, r), 2.2)
    f += blur(body, 110.0) * 0.150
    f += gauss2(cx, cy, r * 2.4) * 0.045

    d = np.sqrt((XS - cx) ** 2 + (YS - cy) ** 2) / r
    inner = np.clip(1.0 - d * d, 0.0, 1.0) ** 0.70
    val = 0.470 + 0.360 * inner + 0.050 * gauss2(cx - r * 0.42, cy - r * 0.46, r * 1.2)
    f = over(f, body, val.astype(np.float32))

    for orb, alpha in ((1.62, 0.045), (2.30, 0.026)):
        ring = cov(np.abs(sd_circle(cx, cy, r * orb)) - 0.55, 1.0)
        f += ring * alpha

    f += gauss2(cx, cy + r * 1.95, r * 1.6, r * 0.34) * 0.032
    return f


def s03_dunes() -> np.ndarray:
    """Three matte ridges, each crest catching a thin line of light."""
    f = sky(0.208, 0.168, [(0.70, 0.12, 0.62, 0.030)], 0.16)
    layers = [
        (0.452, 0.044, 0.95, 0.35, 0.176),
        (0.588, 0.060, 1.35, 2.10, 0.146),
        (0.740, 0.052, 0.80, 4.20, 0.120),
    ]
    for base, amp, freq, phase, tone in layers:
        edge = (base + amp * np.sin(TAU * (freq * XN + phase)) + 0.075 * XN - 0.036) * H
        below = sstep(-1.8, 1.8, YS - edge)
        depth = np.clip((YS - edge) / (H * 0.42), 0.0, 1.0)
        f = f * (1.0 - below) + below * (tone - 0.014 * depth)
        crest = np.exp(-0.5 * ((YS - edge) / 1.8) ** 2).astype(np.float32)
        f += crest * 0.32 + blur(crest, 8.0) * 0.210
    f += gauss2(0.16 * W, 0.08 * H, 0.55 * W, 0.30 * H) * 0.024
    return f


def s04_lattice() -> np.ndarray:
    """A fine dot lattice dissolving into a diagonal pool of light."""
    f = sky(0.190, 0.156, [(0.34, 0.40, 0.52, 0.028)], 0.10)
    sp = 52.0
    mx = np.abs(((XS - sp * 0.5) % sp) - sp * 0.5)
    my = np.abs(((YS - sp * 0.5) % sp) - sp * 0.5)
    d = np.sqrt(mx * mx + my * my)
    dots = np.clip(1.0 - (d - 1.05) / 1.35, 0.0, 1.0) ** 1.4

    ang = math.radians(-24.0)
    u = (XS - 0.38 * W) * math.cos(ang) + (YS - 0.52 * H) * math.sin(ang)
    pool = np.exp(-0.5 * (u / (W * 0.30)) ** 2).astype(np.float32)
    f += dots * (0.34 + 0.80 * pool) * 0.195
    f += blur_big(pool, 90.0) * 0.075

    f += gauss2(0.80 * W, 0.72 * H, 0.34 * W, 0.40 * H) * 0.022
    return f


def s05_eclipse() -> np.ndarray:
    """A dark sphere with one lit limb and quiet atmospheric rings."""
    f = sky(0.204, 0.162, [(0.22, 0.16, 0.62, 0.032)], 0.18)
    cx, cy, r = 0.585 * W, 0.500 * H, 0.243 * W

    for orb, alpha in ((1.30, 0.032), (1.62, 0.020)):
        ring = cov(np.abs(sd_circle(cx, cy, r * orb)) - 0.65, 1.1)
        f += ring * alpha

    limb_c = math.radians(-42.0)
    ang = np.arctan2(YS - cy, XS - cx)
    delta = np.abs((ang - limb_c + math.pi) % TAU - math.pi)
    radial = np.exp(-0.5 * ((np.sqrt((XS - cx) ** 2 + (YS - cy) ** 2) - r * 0.975) / (r * 0.020)) ** 2)
    limb = (np.exp(-0.5 * (delta / 0.70) ** 2) * radial).astype(np.float32)

    body = cov(sd_circle(cx, cy, r), 2.2)
    shade = 0.122 + 0.046 * gauss2(cx - r * 0.55, cy - r * 0.60, r * 1.25)
    f = over(f, body, shade)

    spec(f, limb * (1.0 - body), 0.620, 0.280, 7.0)
    f += gauss2(cx + r * math.cos(limb_c) * 1.03, cy + r * math.sin(limb_c) * 1.03, r * 0.36) * 0.075
    f += gauss2(cx, cy, r * 1.9) * 0.018
    return f


def s06_monolith() -> np.ndarray:
    """A tall pale slab, lit from the left, floating in still air."""
    f = sky(0.206, 0.164, [(0.20, 0.10, 0.58, 0.028)], 0.18)
    cx, cy = 0.596 * W, 0.462 * H
    w, h = 0.092 * W, 0.660 * H
    r = 0.0075 * W

    f += gauss2(cx, cy, w * 2.4, h * 0.62) * 0.030

    sd = sd_rrect(cx, cy, w, h, r)
    body = cov(sd, 1.5)

    f += blur_big(body, 120.0) * 0.050
    f += blur(body, 30.0) * 0.060
    f -= blur_big(cov(sd_rrect(cx + 26, cy + 30, w * 1.10, h * 1.01, r), 2.0), 80.0) * 0.050

    across = sstep(0.0, 1.0, np.clip(((XS - (cx - w * 0.5)) / w), 0.0, 1.0))
    ystep = sstep(0.0, 1.0, np.clip((YS - (cy - h * 0.5)) / h, 0.0, 1.0))
    val = 0.760 - 0.560 * across + 0.070 * (1.0 - ystep)
    f = over(f, body, val.astype(np.float32))

    left = cov(np.abs(XS - (cx - w / 2)) - 0.55, 1.1) * body
    spec(f, left, 0.115, 0.230, 18.0)
    top = cov(np.abs(YS - (cy - h / 2)) - 0.50, 1.0) * body
    f += top * 0.115
    inner = cov(np.abs(sd_rrect(cx, cy, w - 13, h - 13, r * 0.7)) - 0.45, 1.0)
    f += inner * 0.075

    f += gauss2(cx, cy + h * 0.545, w * 1.6, 26.0) * 0.080
    return f


def s07_silk() -> np.ndarray:
    """Four satin folds, lit along the crests, deep between."""
    f = sky(0.180, 0.140, [(0.58, 0.08, 0.56, 0.022)], 0.14)
    folds = [
        (0.235, 0.036, 1.10, 0.30, 0.104, 0.340),
        (0.412, 0.044, 1.45, 1.90, 0.096, 0.320),
        (0.590, 0.036, 0.95, 3.30, 0.102, 0.300),
        (0.772, 0.040, 1.30, 4.70, 0.090, 0.275),
    ]
    for y0, amp, freq, phase, thick, peak in folds:
        crest = (y0 + amp * np.sin(TAU * (freq * XN + phase)) + 0.045 * XN) * H
        depth = YS - crest
        t = np.clip(depth / (thick * H), 0.0, 1.0)
        shape = 1.0 - t * t * (3 - 2 * t)
        inside = np.where(depth >= 0.0, shape, 0.0).astype(np.float32)
        fill = inside * (peak * (1.0 - 0.70 * t))
        f += blur(fill, 4.5) * 0.90

        crestln = (np.exp(-0.5 * (depth / 1.6) ** 2) * (depth > -1.0)).astype(np.float32)
        spec(f, crestln, peak * 1.10, peak * 0.42, 6.0)

        under = np.exp(-0.5 * ((depth - thick * H * 0.82) / (H * 0.018)) ** 2).astype(np.float32)
        f -= blur(under, 16.0) * 0.060

    f += gauss2(0.10 * W, 0.04 * H, 0.40 * W, 0.20 * H) * 0.024
    return f


def s08_contour() -> np.ndarray:
    """Topographic rings under a single blade of light."""
    f = sky(0.202, 0.168, [(0.26, 0.16, 0.56, 0.022)], 0.16)
    cx, cy = 0.315 * W, 0.690 * H

    for i in range(1, 21):
        r = i * 0.0302 * W
        a = 0.175 * (1.0 - i / 23.0) ** 1.4
        ring = cov(np.abs(sd_circle(cx, cy, r) * 0.84) - 0.50, 1.0)
        fade = 0.45 + 0.55 * np.clip((YS - (cy - r)) / (2 * r), 0, 1)
        f += ring * fade * a

    ang = math.radians(-16.0)
    u = (XS - 0.5 * W) * math.cos(ang) + (YS - 0.55 * H) * math.sin(ang)
    v = -(XS - 0.5 * W) * math.sin(ang) + (YS - 0.55 * H) * math.cos(ang)
    blade = np.exp(-0.5 * (u / (H * 0.058)) ** 2).astype(np.float32)
    f += blur_big(blade, 46.0) * 0.085
    f += blur(blade, 6.0) * 0.040
    spec(f, cov(np.abs(u) - 0.45, 1.1), 0.090, 0.200, 11.0)

    ticks = (np.abs(np.abs(u) - H * 0.0125) < 0.55) & ((v % (H * 0.055)) < H * 0.022)
    f += ticks.astype(np.float32) * 0.115

    f += gauss2(cx, cy, W * 0.14, H * 0.14) * 0.038
    return f


def s09_prism() -> np.ndarray:
    """Three glass plates stacked in quiet light, crescent mark."""
    f = sky(0.198, 0.158, [(0.50, 0.42, 0.46, 0.026)], 0.16)
    f += gauss2(0.55 * W, 0.46 * H, W * 0.26) * 0.030

    plates = [
        dict(rot=42.0, size=0.400, dx=-0.050, dy=0.030, hi=0.395, lo=0.150, edge=0.55),
        dict(rot=16.0, size=0.328, dx=0.044, dy=-0.020, hi=0.465, lo=0.165, edge=0.72),
        dict(rot=0.0, size=0.262, dx=-0.004, dy=0.004, hi=0.545, lo=0.190, edge=0.90),
    ]
    for p in plates:
        side = p["size"] * W
        cx = W * (0.55 + p["dx"])
        cy = H * (0.47 + p["dy"])
        rot = math.radians(p["rot"])
        sd = sd_rrect(cx, cy, side, side, side * 0.150, rot)
        body = cov(sd, 1.6)

        f += blur_big(body, 90.0) * 0.028
        u = (XS - cx) * math.cos(rot) + (YS - cy) * math.sin(rot)
        v = -(XS - cx) * math.sin(rot) + (YS - cy) * math.cos(rot)
        gloss = np.clip(0.86 - 0.46 * (v / side) - 0.30 * (u / side), 0.0, 1.0) ** 0.9
        val = (p["lo"] + (p["hi"] - p["lo"]) * gloss).astype(np.float32)
        f = over(f, body, val)

        edge = cov(np.abs(sd) - 0.55, 1.1)
        spec(f, edge, p["edge"] * 0.30, p["edge"] * 0.16, 9.0)
        inner = cov(np.abs(sd_rrect(cx, cy, side - side * 0.045, side - side * 0.045, side * 0.130, rot)) - 0.45, 1.0)
        f += inner * 0.070
        sheen = np.exp(-0.5 * ((u / (side * 0.22)) ** 2)).astype(np.float32) * body
        f += sheen * 0.055

    side = plates[2]["size"] * W
    cx, cy = W * 0.55, H * 0.474
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
    f *= 1.0 - 0.40 * shadow
    f += mark * 0.62 + dot * 0.74
    f += gauss2(cx, cy, side * 0.34) * 0.026
    return f


def s10_beacon() -> np.ndarray:
    """A shaft of light standing in low fog."""
    f = sky(0.196, 0.160, [(0.34, 0.40, 0.36, 0.020)], 0.16)
    ang = math.radians(-13.0)
    u = (XS - 0.40 * W) * math.cos(ang) + (YS - 0.50 * H) * math.sin(ang)
    v = -(XS - 0.40 * W) * math.sin(ang) + (YS - 0.50 * H) * math.cos(ang)

    shaft = (np.exp(-0.5 * (u / (W * 0.038)) ** 2) * (0.42 + 0.58 * sstep(-0.55 * H, 0.38 * H, v))).astype(np.float32)
    f += blur_big(shaft, 70.0) * 0.115
    f += blur(shaft, 9.0) * 0.050

    core = (np.exp(-0.5 * (u / 1.3) ** 2) * np.exp(-0.5 * (v / (H * 0.40)) ** 2)).astype(np.float32)
    spec(f, core, 0.240, 0.160, 26.0)

    f += gauss2(0.43 * W, 0.60 * H, W * 0.20, H * 0.13) * 0.055
    f += gauss2(0.26 * W, 0.96 * H, W * 0.38, H * 0.08) * 0.030
    f += gauss2(0.68 * W, 0.06 * H, W * 0.30, H * 0.10) * 0.020

    rng = np.random.default_rng(9)
    dust = np.zeros((H, W), dtype=np.float32)
    idx = rng.integers(0, H * W, 800)
    np.add.at(dust.reshape(-1), idx, rng.uniform(0.20, 0.85, idx.size).astype(np.float32))
    f += blur(dust, 1.2) * 0.15
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
