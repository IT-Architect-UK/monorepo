# logo-dark.png — how it is generated

Source: `Logos/IT Architect/PNG/LOGO-TRANSPARENT-BG.png` (4208x1764), NOT the
858px `logo.png` in this folder. Deriving from the website copy leaves a dark
fringe around the letters, because the original antialiasing is dark ink.

The 3D look is Photoshop BevelEmboss + DropShadow baked into pixels as tonal
variation — the red alone carries ~387 distinct tones. A flat fill destroys all
of it and the result looks dead, so the recolour must PRESERVE relative
luminance and only shift it into the light range.

Method:
1. Classify ink: red-hued (ARCHITECT + cloud) vs neutral (icon, IT, tagline).
2. Separate the drop shadow from antialiasing. Both are soft-alpha black, so
   dilate the solid-ink mask by ~4px: soft pixels touching solid ink are
   antialiasing and are kept; the broad offset halo is shadow and its alpha is
   zeroed. Brightening the shadow would produce a white halo; deleting all soft
   pixels would leave jagged edges.
3. Remap luminance per class, monotonically, into a light band:
   out = floor + (1 - floor) * t^gamma,  t = normalised source luminance
   Shipped values (V3, "whitest"): red floor 0.80 gamma 0.40,
   neutral floor 0.86 gamma 0.45.
4. Crop to the ink bbox and resample once to 858x327 (LANCZOS) so it matches
   logo.png exactly — the two swap on theme change and any size difference
   would shift the header.

Do not regenerate `logo.png` from the master: measured against the current
file it comes out slightly softer, so the existing light logo stays as it is.
