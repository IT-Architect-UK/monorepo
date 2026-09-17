# Dashboard sign-in: why does a fresh session still 401 on a form post?
Status: open
Owner: Darren (VPS shell or Webmin terminal), Cowork for the browser part
Written by Claude Code, 2026-09-17.

## Context

Cowork's live check (`2026-09-17-verify-signin-fix-and-manual-send.md`)
shows the refreshed-cookie fix is not the whole story: a POST bounced to
`/?resend=1` about one minute after a successful submit, on a session
signed in six minutes earlier. oauth2-proxy v7.15.4's code
(`pkg/middleware/stored_session.go`) only re-validates a session after a
refresh, and only refreshes once the session is older than
`cookie_refresh` (1 h here). So a 401 on a six-minute-old session means
`store.Load` returned nothing: the cookie oauth2-proxy received did not
decode, was missing a chunk, or was not the cookie it had just set.
Which of those needs the logs. Claude Code has no route to the VPS.

## Do this

Cowork, in the browser: open https://dashboard.itsurgery.me/webmin-frame,
sign in to Webmin, open Tools > Command Shell (or Terminal). Run this
one command, which writes a short filtered log file into the repo clone
on the VPS:

```
{ echo "== oauth2-proxy"; docker logs oauth2-proxy --since 2026-09-17T13:55:00Z --until 2026-09-17T14:12:00Z 2>&1 | grep -iE ' 401 |error|refresh|invalid|expired|cookie' | grep -v ' 202 '; echo "== nginx"; grep '17/Sep/2026:14:0' /var/log/nginx/access.log | grep -E 'oauth2/start|oauth2/callback|POST /webhook/custom-job|" 401 '; echo "== config"; docker exec oauth2-proxy sh -c 'grep -E "^cookie_(name|expire|refresh|samesite)" /etc/oauth2-proxy.cfg'; docker inspect oauth2-proxy --format '{{.Config.Image}} started {{.State.StartedAt}}'; } > /opt/monorepo/docs/handoffs/signin-401-logs.txt; wc -l /opt/monorepo/docs/handoffs/signin-401-logs.txt
```

Then, still in that shell:

```
cd /opt/monorepo && git pull && git add docs/handoffs/signin-401-logs.txt && git commit -m "Sign-in 401: filtered logs for Claude Code" && git push
```

If the push needs credentials the shell does not have, paste the file's
contents under Result in this handoff instead and push from wherever you
normally do. Nothing in the file is a secret (no cookie values, no keys).

Claude Code reads the file, works out the cause, and removes the file
from the repo.

## Result

(filled in by Darren / Cowork)
