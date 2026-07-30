# IT Surgery logo

## How to rebuild it

```bash
python3 tools/build-logo.py 0.16 out      # writes out_{light,dark}_{1,2,3}x.png
```

The script rebuilds the wordmark from the 2008 Illustrator vector in
`Logos/IT Surgery/Masters/IT_Surgery_Logo.eps` — it does not edit a finished
bitmap, so the output can be regenerated at any size. The argument is the bevel
width as a fraction of stroke width; see below.

Six files are deployed: `logo.png`, `logo@2x.png`, `logo@3x.png` and the three
`logo-dark*` equivalents. The 1x file is **179x55 for a 177x54 paint area** —
deliberately a fraction over, never under. Upscaling a bitmap reintroduces the
exact blur this setup removes.

## The three things that made it look blurred, and the fixes

**1. The bevel was sized by logo height, so it covered the whole stroke.**
This was the real cause. The bevel band was `height x 0.030`, which on a stroke
only 8px wide at the painted size left no flat core at all — every letter was a
soft gradient from edge to edge. Measured as interior luminance spread across a
stroke at the painted size:

| | spread |
|---|---|
| Old asset | 88 |
| IT Architect logo (the one that looks good) | 57 |
| **This build, bevel 16% of stroke** | **25** |

The fix is that the bevel is now measured as a fraction of **stroke width**, not
of logo height, so a flat core always survives however small the logo is drawn.
`0.16` matches the proportion IT Architect uses. Lower values are flatter and
crisper, higher values are more three-dimensional and softer — 0.10 gives 18,
0.13 gives 22.

**2. Every visitor got a 6x browser downscale.** The old asset was 1106px wide
painted at 177px. Browsers resample cheaply, and that was most of the remaining
softness. `srcset` density descriptors now hand each display an asset at its own
density.

**3. The artwork was clipped on all four sides.** Max alpha at the old asset's
top/bottom/left/right edges was 255/255/234/112 — 255 means a stroke cut
mid-flight. `grey_dilation` cannot grow past the canvas edge, so thickening a
tightly-cropped master shaved the outer strokes flat. The script now pads the
canvas before dilating; edge alpha is now 11/4/5/4.

Because the artwork now carries that margin, the CSS height went 3.2rem to
3.4rem. Without it the letters would render 4% smaller at the same canvas
height. This keeps the cap height as approved **and** the lockup at 177px wide,
so the strapline breakpoints below still hold.

## Two things not to break

**The gap between the "i" and its dot.** Plain dilation closes it. The script
uses a seam-aware dilation: it labels the separate glyph components, finds the
watershed between them, and refuses to grow ink across it. Verify after any
change — at a common 320px height the artwork must have **9 separate components
and a 6px gap**. Eight components means the dot has merged into the stem.

**Do not go back to editing the finished PNG.** An earlier attempt flat-filled
the letterforms and collapsed 387 red tones to 2, destroying the bevel. If a
change is needed, change the script and re-render from the vector.

## Constraints to keep

- Light and dark files must be **identical pixel dimensions**, or the header
  shifts when the theme is toggled.
- The theme swap selectors must stay scoped to `.brand` — a bare `.logo-dark`
  is specificity (0,1,0) and loses to `.brand img`, leaving both logos visible
  and doubling the header height.
- The strapline sits beside the logo and is hidden between 961-1180px and below
  641px, because the lockup plus the nav does not fit. Changing the logo width
  changes those thresholds.

## Approaches that were tried and rejected

Kept so they are not attempted again. All of these operated on the finished
artwork rather than the vector, which is why they failed:

- Thickening by stroking cannot work on the tube. In the vector the stethoscope
  is a **rectangle given its shape by a clipPath**, so stroking it draws a
  rectangle outline across the artwork.
- A keyline drawn with `paint-order` is unreliable — where a renderer ignores
  the property the stroke paints over the fill and thins the letterforms.
- `feSpecularLighting` washes the colour out. SVG filters default to
  **linearRGB**; `color-interpolation-filters="sRGB"` is the fix. Even then, on
  a flat interior it still returns light.
- A bevel band is `shape MINUS shape-offset`. Clipping an offset copy to the
  shape covers the whole interior instead of forming an edge band.

A true vector rebuild — letterforms redrawn at a heavier weight with the bevel
in the artwork, delivered as SVG — would still scale better than any bitmap. If
that is ever wanted it is type work for a designer (£20-50 on Fiverr or
PeoplePerHour): supply `IT_Surgery_Logo.eps`, ask for heavier stroke weight, a
red-to-black gradient across "rg", crisp edges and subtle 3D, as SVG plus PNG in
light and dark variants.
