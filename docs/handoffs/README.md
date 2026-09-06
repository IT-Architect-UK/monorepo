# Handoffs between Claude Code and Claude Cowork / Chrome

Two kinds of Claude work on this repo and they cannot see each other's chats:

- **Claude Code** works in the repo: the site, scripts, automation, docs. It has
  no browser, no logins, no way to click through a web app.
- **Claude Cowork / Claude in Chrome** works on Darren's machine and in his
  browser: Cal.com, Meta Business Suite, Google Ads and Analytics, Netlify,
  EspoCRM, Xero, and running scripts that need secrets from Bitwarden.

The repo is the one thing both can read and write, so it is the handoff
channel. Nothing is pasted between chats.

## The convention

One file per task in this directory, named `YYYY-MM-DD-topic.md`, with three
sections:

```
# <title>
Status: open | done | blocked

## Context
What this is about and why, with paths, URLs and expected values, so the
reader needs nothing from the other chat.

## Do this
Numbered steps. Name the Bitwarden entry for any secret; never the secret.
Say what the expected outcome looks like and when to stop and ask.

## Result
Filled in by whoever did the work: what was run, what was seen, what was
changed, anything that differed from the plan. Then set Status.
```

Whichever agent needs the other creates the file with Context and Do this,
sets `Status: open`, and commits. The other agent pulls, does the work, fills
in Result, sets the status, and commits. Files stay here afterwards as the log.

## Telling an agent to use it

To Cowork: *"Pull the monorepo, read CLAUDE.md and docs/handoffs/README.md,
then work the open handoff(s) in docs/handoffs and commit the result."*

To Claude Code: *"Cowork has finished a handoff; read docs/handoffs and carry on."*

Both agents read `CLAUDE.md` first: it says what deploys on push and which
kind of Claude does what.
