#!/usr/bin/env python3
"""
Render a built page at a given viewport width.

Why this exists: WeasyPrint silently ignores width media queries, so rendering a
page at a narrow page size shows the DESKTOP layout at a narrow width. Every
"mobile check" done that way is worthless, and a broken phone layout ships.

This resolves @media by hand before rendering — matching blocks are spliced in
where they sat, so cascade order is preserved; non-matching blocks are dropped.
The result is CSS that is already correct for that width, which WeasyPrint can
render honestly.

Still not a browser: flexbox and grid support is partial, so treat this as a
check on wrapping, stacking and overflow rather than a pixel-accurate preview.

    python3 tools/render-viewport.py _site/fixed-prices/index.html 390 out.png
"""
import re, sys, os
import tinycss2
import weasyprint, logging
logging.getLogger("weasyprint").setLevel(logging.ERROR)

def matches(prelude, width):
    q = tinycss2.serialize(prelude).strip().lower()
    if "print" in q and "screen" not in q:
        return False
    for lo in re.findall(r"min-width:\s*(\d+)px", q):
        if width < int(lo): return False
    for hi in re.findall(r"max-width:\s*(\d+)px", q):
        if width > int(hi): return False
    return True

def flatten(css, width):
    out = []
    for rule in tinycss2.parse_stylesheet(css, skip_whitespace=True):
        if rule.type == "at-rule" and rule.lower_at_keyword == "page":
            continue   # author @page would override the requested viewport size
        if rule.type == "at-rule" and rule.lower_at_keyword == "media":
            if matches(rule.prelude, width):
                out.append(flatten(tinycss2.serialize(rule.content), width))   # nested @media
        else:
            out.append(tinycss2.serialize([rule]))
    return "\n".join(out)

def render(page, width, png, height=4000, theme=None):
    # Walk up from the page's own directory, not its parent: a page at the site
    # root (index.html) already sits beside assets/, and starting a level up
    # skipped it and silently loaded no CSS at all.
    site = os.path.dirname(os.path.abspath(page))
    while not os.path.isdir(os.path.join(site, "assets")) and site != "/":
        site = os.path.dirname(site)
    html = open(page).read()
    if theme:
        html = html.replace('<html lang="en-GB">', '<html lang="en-GB" data-theme="%s">' % theme)
    sheets = []
    for href in re.findall(r'<link[^>]+href="([^"]+\.css[^"]*)"', html):
        path = os.path.join(site, href.split("?")[0].lstrip("/"))
        if os.path.exists(path):
            sheets.append(weasyprint.CSS(string=flatten(open(path).read(), width)))
    html = re.sub(r'<link[^>]+\.css[^>]*>', "", html)
    doc = weasyprint.HTML(string=html, base_url=site + "/").render(
        stylesheets=[weasyprint.CSS(string="@page{size:%dpx %dpx;margin:0}" % (width, height))] + sheets)
    doc.write_pdf("/tmp/_vp.pdf")
    import pypdfium2 as pdfium
    pdfium.PdfDocument("/tmp/_vp.pdf")[0].render(scale=2).to_pil().save(png)
    return doc

if __name__ == "__main__":
    page, width, png = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    theme = sys.argv[4] if len(sys.argv) > 4 else None
    render(page, width, png, theme=theme)
    print("rendered %s at %dpx -> %s" % (page, width, png))
