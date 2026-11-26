# Your website with its status page (chapter 11, tier 2), character pages and sign-in (chapter 11, tier 3):
# replaces the character pages' Dockerfile. Coolify builds this on every merge. The settings (the API's, and
# AUTH_*, SITE_URL, SESSION_SECRET, SSO_COOKIE_DOMAIN for signing in) are in the application's environment in
# Coolify, read when the container starts, never built into the image.
FROM nginx:1.29-alpine
COPY nginx.conf /etc/nginx/nginx.conf
COPY status.js characters.js characters.txt auth.js /etc/nginx/
COPY index.html status.html characters.html character.html account.html /usr/share/nginx/html/
COPY embed /usr/share/nginx/html/embed
