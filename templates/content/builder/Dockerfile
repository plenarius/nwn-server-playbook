# The builder image for your custom content (chapter 7, tier 2): the neverwinter.nim tools at one version, checked
# against a known checksum, and nothing else. publish.sh builds it once, on the control host, and runs every
# build, write, check and tidy-up in it, so the tools never change under you unless you change these two lines.
#
#   docker build -t nwsync-builder:2.3.2 ~/content/builder
#
# A new version of the tools: change both lines (the checksum is "sha256sum" of the release zip) and the tag in
# content.env, then build again.
FROM ubuntu:24.04

ARG NWN_TOOLS_VERSION=2.3.2
ARG NWN_TOOLS_SHA256=f6c896f2821315acc70d2dffd2b8f86f17aa4fc2a549412864c1eab37aadcb19

# curl, the certificates and aria2 fetch your download address over HTTPS, as a player's game does, for the
# check in publish.sh (nwsync-check). (The tools' own fetch tool can't: the release is built without HTTPS.)
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip aria2 \
 && curl -fsSL -o /tmp/nw.zip \
      "https://github.com/niv/neverwinter.nim/releases/download/${NWN_TOOLS_VERSION}/neverwinter-x86_64-linux-gnu.zip" \
 && echo "${NWN_TOOLS_SHA256}  /tmp/nw.zip" | sha256sum -c --quiet - \
 && unzip -q /tmp/nw.zip -d /usr/local/bin nwn_erf nwn_gff nwn_tlk \
      nwn_nwsync_write nwn_nwsync_print nwn_nwsync_prune \
 && rm /tmp/nw.zip \
 && apt-get purge -y unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

COPY nwsync-check /usr/local/bin/nwsync-check

# Refuse to build an image whose tools say they are another version.
RUN nwn_nwsync_write --version | grep -q "^neverwinter ${NWN_TOOLS_VERSION} "

LABEL org.opencontainers.image.description="neverwinter.nim ${NWN_TOOLS_VERSION} tools for building haks, talk tables and NWSync"
