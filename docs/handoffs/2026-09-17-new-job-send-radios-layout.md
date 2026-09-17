# New job form: the Send radio labels wrap one word per line

Status: done
Owner: Claude Code. Small and urgent - ship on its own, before the sign-in rework.

## Context

Since 39049ff the New job form's Send fieldset renders as:

    ( )  Email it
         from Xero
         now
    ( )  I'll send
         it
         myself

(Darren's screenshot, 2026-09-17 evening.) Cause, in `dashboard.json`
"Build the page" CSS: line ~191 `.job input,.job select{display:block;width:100%;...}`
also matches the two `<input type="radio" name="send">` inside
`fieldset.send` (line ~248-249). A radio at `width:100%` inside the
`display:flex` label leaves the text a few pixels wide, so it wraps at
every space. `.send label{display:flex;...}` (line ~202) styles the label
but nothing overrides the input rule.

## Do this

1. Add after line ~202: `.send input{display:inline-block;width:auto;margin:0}`
   (same specificity as `.job input`, later in the sheet, so it wins). Or
   scope the original: `.job input:not([type=radio])`.
2. Check the fieldset at 400 px and at desktop width: both options on one
   line each, radio then text, side by side within the fieldset
   (`flex-wrap` keeps them stacking on narrow screens).
3. Deploy (deploy-n8n.yml), then reload dashboard.itsurgery.me and put a
   one-line confirmation in Result.

## Result

Claude Code, 2026-09-17. Added `.send input{display:inline-block;width:auto;margin:0}`
after the `.send label` rule. Rendered and measured in Chromium: at 400 px
and 1100 px each option is one line (label height 18 px / 14 px, radio
13 px / 10 px wide, text beside it). Deployed by this push; the reload
check on the live page is Darren's or Cowork's.

