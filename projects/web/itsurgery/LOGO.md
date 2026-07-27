# IT Surgery logo — current state and what is outstanding

## What is deployed

`src/assets/logo.png` and `logo-dark.png`, the artwork approved at commit
`d67552d`. Derived from the original 2008 Illustrator vector in
`Logos/IT Surgery/Masters/IT_Surgery_Logo.eps`: red-to-black gradient running
across "rg", a bevel lit from directly above, and a soft drop shadow. 1107x320,
displayed at 51px tall in the header.

## Outstanding — needs a designer, not more image processing

Darren's brief: **thicker letterforms, gradient colour, crisply defined edges,
and the 3D depth of the IT Architect logo.** Several attempts to produce this by
manipulating the finished artwork were all rejected, and the reasons are
structural rather than a matter of tuning:

- Thickening by stroking cannot work on the tube. In the vector the stethoscope
  is a **rectangle given its shape by a clipPath**, so stroking it draws a
  rectangle outline across the artwork.
- A keyline drawn with `paint-order` is unreliable — where a renderer ignores
  the property the stroke paints over the fill and thins the letterforms, so
  making it thicker makes the logo look worse.
- `feSpecularLighting` washes the colour out. SVG filters default to
  **linearRGB**; `color-interpolation-filters="sRGB"` is the fix, and the
  specular must be added with `feComposite operator="arithmetic"` rather than
  merged over. Even then, on a flat interior it still returns light.
- A bevel band is `shape MINUS shape-offset`. Clipping an offset copy to the
  shape covers the whole interior instead of forming an edge band.

What the brief actually needs is the letterforms redrawn at a heavier weight in
the vector, with the bevel built into the artwork. That is type work.

**Suggested brief for a designer** (£20-50 on Fiverr or PeoplePerHour): supply
`IT_Surgery_Logo.eps`; ask for heavier stroke weight, a red-to-black gradient
across "rg", crisp defined edges, subtle 3D, delivered as SVG plus PNG in
light-background and dark-background variants.

## Constraints to keep whatever replaces it

- Light and dark files must be **identical pixel dimensions**, or the header
  shifts when the theme is toggled.
- The theme swap selectors must stay scoped to `.brand` — a bare `.logo-dark`
  is specificity (0,1,0) and loses to `.brand img`, leaving both logos visible
  and doubling the header height.
- The strapline sits beside the logo and is hidden between 961-1180px and below
  641px, because the lockup plus the nav does not fit. Changing the logo width
  changes those thresholds.
