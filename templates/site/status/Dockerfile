# Your website with its status page (chapter 11, tier 2): replaces the two-line Dockerfile of the first part.
# Coolify builds this on every merge. Set OPS_API_URL and OPS_API_READ_KEY in the application's environment in
# Coolify; they are read when the container starts, never built into the image.
# Add a COPY line for each further file or folder, for example:  COPY images /usr/share/nginx/html/images
FROM nginx:1.29-alpine
COPY nginx.conf /etc/nginx/nginx.conf
COPY status.js /etc/nginx/status.js
COPY index.html status.html /usr/share/nginx/html/
