# Authentik with your configuration built in (chapter 11, tier 3). The blueprints folder is copied into the image,
# and Authentik's worker applies every file in it when it starts, and again whenever one changes. So a merged pull
# request that changes a blueprint is a deploy like any other: Coolify builds this, starts it, and the change is
# live a minute later. Pin the version: an upgrade is its own pull request, after reading the release notes.
FROM ghcr.io/goauthentik/server:2026.8.7
COPY --chown=1000:1000 blueprints/ /blueprints/custom/
