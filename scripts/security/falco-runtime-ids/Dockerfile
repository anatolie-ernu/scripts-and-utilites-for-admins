ARG FALCO_VERSION=0.45.2
FROM docker.io/falcosecurity/falco:${FALCO_VERSION}

USER root

COPY config/10-ernu-runtime.yaml /etc/falco/config.d/10-ernu-runtime.yaml
COPY rules.d/ /etc/falco/rules.d/

# Falco itself remains the runtime process supplied by the upstream image.
