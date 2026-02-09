ARG BASE_IMAGE=gitlab/gitlab-runner:alpine-v17.11.7
FROM ${BASE_IMAGE}

ARG CI_APK_PACKAGES="bash curl jq yq ripgrep git openssh-client ca-certificates"

USER root
RUN set -eux; \
    apk add --no-cache ${CI_APK_PACKAGES}; \
    update-ca-certificates

