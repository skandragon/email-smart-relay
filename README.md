# email-smart-relay
Relay all incoming email to an external provider.

## Motivation

My home lab has several Proxmox and other servers which sometimes want to mail me about
important things.  While I used to run my own SMTP server and handle this for my
whole domain, the spam is just too much to filter out well, and I decided to move
to a hosted SMTP provider.

Unfortunately, this makes email somewhat harder to handle for all these one-off
services, and I didn't want to spread my SMTP credentials all over.

This Docker container allows me to set it up somewhere in my environment, and
point all these internal SMTP-sending services to one place, which can then
properly deliver to my inbox.

As credentials are used (if set), it can mail to anywhere, not just to me of course.

--Michael
