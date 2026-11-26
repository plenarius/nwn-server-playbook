# The image each self-hosted runner runs in (chapter 8, tier 3): GitHub's own runner image, plus the GitHub CLI and
# Docker Compose that the module's workflows use, plus the hook that refuses jobs from forks. Build it on the
# control host:   docker build -t nwn-runner:2.338.2 .
FROM ghcr.io/actions/actions-runner:2.338.2

USER root
# Pinned, with the checksums from each project's release page.
ARG GH_VERSION=2.104.0
ARG GH_SHA256=98cb101ad87dbbd3f6b2f2bfcbd43197ccd07643140121d8a9cfaa91eadbc24e
ARG COMPOSE_VERSION=v5.7.1
ARG COMPOSE_SHA256=af426722a8af5de812fcee30cc1c39f0639f5f723cbadefb25e5d4db054064cf
RUN set -eu; cd /tmp; \
    curl -fsSLo gh.tgz "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz"; \
    echo "${GH_SHA256}  gh.tgz" | sha256sum -c -; \
    tar xzf gh.tgz --strip-components=2 -C /usr/local/bin "gh_${GH_VERSION}_linux_amd64/bin/gh"; rm gh.tgz; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    curl -fsSLo /usr/local/lib/docker/cli-plugins/docker-compose \
      "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64"; \
    echo "${COMPOSE_SHA256}  /usr/local/lib/docker/cli-plugins/docker-compose" | sha256sum -c -; \
    chmod 755 /usr/local/lib/docker/cli-plugins/docker-compose; \
    # A job needs no root: take the runner user out of the sudo group.
    gpasswd -d runner sudo
COPY hooks/job-started.sh /home/runner/hooks/job-started.sh
# The runner runs this before every job, and a job it refuses fails before its first step.
ENV ACTIONS_RUNNER_HOOK_JOB_STARTED=/home/runner/hooks/job-started.sh
USER runner
