#!/usr/bin/env python3
"""
Rebuild the IT Surgery wordmark from the Illustrator master.

Pipeline: vector master -> raster at high DPI -> thicken (seam-aware, so the
gap over the "i" survives) -> red-to-charcoal gradient -> bevel -> drop shadow
-> crop -> export 1x/2x/3x.

The bevel band is sized as a fraction of MEASURED STROKE WIDTH, not of logo
height. Sizing it by height is what made the earlier build look blurred: the
gradient spanned the whole 8px stroke and left no flat core, so every letter
read as a smudge instead of a solid shape.

Usage: python3 build_logo.py [bevel_fraction_of_stroke] [out_prefix]
"""
import subprocess, sys, os
import numpy as np
from PIL import Image
from scipy import ndimage

EPS   = "/sessions/festive-laughing-dijkstra/mnt/Freelancer/Logos/IT Surgery/Masters/IT_Surgery_Logo.eps"
DPI   = 600           # master density the approved thickness was tuned at
DIL   = 12            # thickening radius, approved at 4.74px rendered
SEAM  = 11            # seam guard that preserves the gap over the "i"
BEVEL_FRAC = float(sys.argv[1]) if len(sys.argv) > 1 else 0.16
PREFIX     = sys.argv[2] if len(sys.argv) > 2 else "b"
RENDER_H   = 55       # 1x must be >= the painted size, never upscaled

# ---------------------------------------------------------------- 1. rasterise
if not os.path.exists("master.png"):
    subprocess.run(["gs", "-dSAFER", "-dBATCH", "-dNOPAUSE", "-sDEVICE=pngalpha",
                    f"-r{DPI}", "-dEPSCrop", "-sOutputFile=master.png", EPS],
                   check=True, capture_output=True)
base = Image.open("master.png").convert("RGBA")

# Pad BEFORE dilating. grey_dilation cannot grow past the canvas edge, so on a
# tightly-cropped master the outermost strokes get shaved flat.
MARGIN = int(DIL * 3 + base.height * 0.06)
a = np.pad(np.array(base).astype(np.float32) / 255.0,
           ((MARGIN, MARGIN), (MARGIN, MARGIN), (0, 0)))
H, W = a.shape[:2]

# ------------------------------------------------------ 2. seam-aware thicken
def dilate_keeping_gaps(A, r, seam_half):
    """Grow the ink, but refuse to grow across a boundary between two separate
    glyph components -- otherwise the dot closes onto the 'i' below it."""
    ink = A > 0.5
    lbl, _ = ndimage.label(ink)
    _, (iy, ix) = ndimage.distance_transform_edt(~ink, return_indices=True)
    nearest = lbl[iy, ix]
    seam = np.zeros_like(ink)
    for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
        seam |= (nearest != np.roll(np.roll(nearest, dy, 0), dx, 1))
    seam &= ~ink
    seam = ndimage.binary_dilation(seam, iterations=seam_half)
    grown = ndimage.gaussian_filter(
        ndimage.grey_dilation(A, size=(r * 2 + 1,) * 2), r * 0.20)
    grown[seam] = 0.0
    return grown

A = dilate_keeping_gaps(a[..., 3], DIL, SEAM)
solid = A > 0.5

# --------------------------------------------- 3. measure the stroke, then bevel
# Distance transform ridge = half the local stroke width.
d = ndimage.distance_transform_edt(solid)
mx = ndimage.maximum_filter(d, 3)
ridge = d[(d > 1) & (d >= mx - 1e-6)]
stroke_px = float(np.median(ridge) * 2)
bevel = max(1.0, stroke_px * BEVEL_FRAC)

# Inset distance, normalised over the bevel band. 0 at the outline, 1 once we
# are a full bevel-width inside -> a flat core, which is what reads as crisp.
inset = np.clip(d / bevel, 0, 1)
# Light from above: the band shades up on top edges, down on bottom edges.
gy, _ = np.gradient(ndimage.gaussian_filter(inset, bevel * 0.5))
shade = np.clip(gy / (np.abs(gy).max() + 1e-9), -1, 1) * 0.50 * (1.0 - inset)

# --------------------------------------------------------------- 4. gradient
ink_cols = np.where(solid.any(axis=0))[0]
x0, x1 = ink_cols[0], ink_cols[-1]
x = (np.arange(W)[None, :].astype(np.float32) - x0) / max(x1 - x0, 1)
u = np.clip((x - 0.40) / 0.20, 0, 1)
ramp = (1.0 - (u * u * (3 - 2 * u)))[..., None]          # smoothstep
RED, CHAR = np.array([0.6, 0.0, 0.0]), np.array([0.137, 0.122, 0.126])
rgb = (RED * ramp + CHAR * (1 - ramp)).astype(np.float32)
rgb = np.broadcast_to(rgb, (H, W, 3)).copy()

# Apply the bevel as a luminance shift, so the hue is untouched.
s = shade[..., None]
rgb = np.where(s > 0, rgb + (1.0 - rgb) * s, rgb * (1.0 + s))
rgb = np.clip(rgb, 0, 1)

# ------------------------------------------------------------- 5. drop shadow
dist, blur, op = H * 0.018, H * 0.026, 0.44
sh = ndimage.gaussian_filter(solid.astype(np.float32), blur / 2.0)
sh = np.roll(sh, int(dist), axis=0) * op

out = np.zeros((H, W, 4), np.float32)
out[..., 3] = A + sh * (1 - A)
np.divide(A[..., None] * rgb, np.maximum(out[..., 3:4], 1e-6), out=rgb)
out[..., :3] = np.clip(rgb, 0, 1)

# ------------------------------------------------------------------- 6. export
def crop_export(arr, tint, prefix):
    o = arr.copy()
    if tint is not None:                       # dark-theme variant: white->grey
        lum = 0.2126*o[...,0] + 0.7152*o[...,1] + 0.0722*o[...,2]
        k = 1.0 - lum / max(lum.max(), 1e-6)
        o[..., :3] = tint[0] * (1 - k[..., None]) + tint[1] * k[..., None]
    im = Image.fromarray((np.clip(o, 0, 1) * 255).astype(np.uint8), "RGBA")
    im = im.crop(im.getchannel("A").point(lambda v: 255 if v > 2 else 0).getbbox())
    w = round(im.width * RENDER_H / im.height)
    for n in (1, 2, 3):
        im.resize((w*n, RENDER_H*n), Image.LANCZOS).save(f"{prefix}_{n}x.png")
    return im, w

full_l, w = crop_export(out, None, f"{PREFIX}_light")
crop_export(out, (np.array([1.0,1.0,1.0]), np.array([0.60,0.64,0.69])), f"{PREFIX}_dark")
print(f"bevel_frac={BEVEL_FRAC}  stroke_master={stroke_px:.1f}px  bevel={bevel:.1f}px  "
      f"master={full_l.width}x{full_l.height}  1x={w}x{RENDER_H}")
