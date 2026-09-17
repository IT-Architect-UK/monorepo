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

On the VPS (or through Webmin's terminal), paste the output of these into
Result. None of them prints a secret.

1. oauth2-proxy's own log for the window Cowork tested (13:50 to 14:15
   UTC on 17 Sep 2026). Every `/oauth2/auth` call is logged with its
   status, and refreshes and load failures are logged in words:

   ```
   docker logs oauth2-proxy --since 2026-09-17T13:50:00Z --until 2026-09-17T14:15:00Z 2>&1 | grep -v "GET /oauth2/auth.*202"
   ```

   (The grep hides the successful auth checks; what is left is the 401s
   and any "Refreshing session", "Unable to refresh", "Error loading
   cookied session", "Cookie ... not present" lines.)

2. The same window from nginx, showing the sign-in bounces and what
   preceded each:

   ```
   grep '17/Sep/2026:1[34]:' /var/log/nginx/access.log | grep -E 'oauth2/(start|callback)|webhook/custom-job|" 401 ' | tail -60
   ```

3. What the running oauth2-proxy was given for the cookie settings
   (names and durations only):

   ```
   docker exec oauth2-proxy sh -c 'grep -E "^cookie_(name|expire|refresh|secure|samesite|domains|path)" /etc/oauth2-proxy.cfg'
   docker inspect oauth2-proxy --format '{{.Config.Image}} started {{.State.StartedAt}}'
   ```

4. In Edge, signed in to dashboard.itsurgery.me: F12 > Application >
   Cookies > https://dashboard.itsurgery.me. List every cookie name that
   starts `_oauth2_proxy` with its size and expiry. (Cowork's extension
   cannot read cookies, so this one is Darren's.)

5. Still open from the previous handoff: void INV-0098 and INV-0099 in
   Xero and delete CRM Contacts 6aabf3f7c6d112821 and 6aabf426bcb0f7700
   ("Test Manual"). Say here when done.

## Result

(filled in by Darren / Cowork)
