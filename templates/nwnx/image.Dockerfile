# Your NWNX image, made the way upstream makes its own: upstream's base image (the game server and the
# libraries the plugins need, without NWNX), plus the NWNX your workflow just built.
# BASE_IMAGE is set in image.yml. Add an apt-get line here if a plugin of yours needs a library the base lacks.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
RUN mkdir -p /nwn/nwnx
ADD NWNX-EE.tar /nwn/nwnx

# Run the server with NWNX, logging through ServerLogRedirector, with every plugin off until switched on.
ENV NWNX_CORE_LOAD_PATH=/nwn/nwnx/ \
    NWN_LD_PRELOAD=/nwn/nwnx/NWNX_Core.so \
    NWNX_SERVERLOGREDIRECTOR_SKIP=n \
    NWN_TAIL_LOGS=n \
    NWNX_CORE_LOG_LEVEL=6 \
    NWNX_SERVERLOGREDIRECTOR_LOG_LEVEL=6 \
    NWNX_CORE_SKIP_ALL=y
