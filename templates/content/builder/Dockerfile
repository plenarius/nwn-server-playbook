# The builder image for your custom content (chapter 7, tiers 2 and 3): the neverwinter.nim tools and cleanmodels,
# each at one version checked against a known checksum. publish.sh builds it once, on the control host, and runs
# every build, compile, write, check and tidy-up in it, so the tools never change under you unless you change
# these lines.
#
#   docker build -t nwsync-builder:2.3.2-cm4.18.3 ~/content/builder
#
# A new version of a tool: change its two lines (the checksum is "sha256sum" of the release zip) and the tag in
# content.env, then build again.
FROM ubuntu:24.04

ARG NWN_TOOLS_VERSION=2.3.2
ARG NWN_TOOLS_SHA256=f6c896f2821315acc70d2dffd2b8f86f17aa4fc2a549412864c1eab37aadcb19
# cleanmodels compiles ASCII models to binary (tier 3, MODELS=compile in content.env).
ARG CLEANMODELS_VERSION=4.18.3
ARG CLEANMODELS_SHA256=17c41fa2f025b512efcbb989a48f7309619145eeec7ff6baf77a53b4288831f7

# curl, the certificates and aria2 fetch your download address over HTTPS, as a player's game does, for the
# check in publish.sh (nwsync-check). (The tools' own fetch tool can't: the release is built without HTTPS.)
# jq reads cleanmodels' findings, and nwn_compressedbuf unpacks downloaded files (chapter 6's fetch_content.sh).
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip aria2 jq \
 && curl -fsSL -o /tmp/nw.zip \
      "https://github.com/niv/neverwinter.nim/releases/download/${NWN_TOOLS_VERSION}/neverwinter-x86_64-linux-gnu.zip" \
 && echo "${NWN_TOOLS_SHA256}  /tmp/nw.zip" | sha256sum -c --quiet - \
 && unzip -q /tmp/nw.zip -d /usr/local/bin nwn_erf nwn_gff nwn_tlk \
      nwn_nwsync_write nwn_nwsync_print nwn_nwsync_prune nwn_compressedbuf \
 && rm /tmp/nw.zip \
 && curl -fsSL -o /tmp/cm.zip \
      "https://github.com/plenarius/cleanmodels/releases/download/v${CLEANMODELS_VERSION}/cleanmodels-linux-amd64.zip" \
 && echo "${CLEANMODELS_SHA256}  /tmp/cm.zip" | sha256sum -c --quiet - \
 && unzip -q -p /tmp/cm.zip cleanmodels-linux-amd64 > /usr/local/bin/cleanmodels \
 && chmod 755 /usr/local/bin/cleanmodels && rm /tmp/cm.zip \
 && apt-get purge -y unzip && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

COPY nwsync-check nwsync-origins /usr/local/bin/

# Refuse to build an image whose tools say they are another version.
RUN nwn_nwsync_write --version | grep -q "^neverwinter ${NWN_TOOLS_VERSION} " \
 && cleanmodels --version | grep -q "^cleanmodels v${CLEANMODELS_VERSION} "

LABEL org.opencontainers.image.description="neverwinter.nim ${NWN_TOOLS_VERSION} and cleanmodels ${CLEANMODELS_VERSION} for building haks, talk tables and NWSync"
