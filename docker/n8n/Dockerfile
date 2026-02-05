ARG BASE_IMAGE=n8nio/n8n:1.122.4
FROM ${BASE_IMAGE}

USER root
RUN set -eux; \
    if command -v apk >/dev/null 2>&1; then \
      apk add --no-cache postgresql15-client ca-certificates; \
      update-ca-certificates; \
    elif command -v apt-get >/dev/null 2>&1; then \
      apt-get update; \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends postgresql-client ca-certificates; \
      rm -rf /var/lib/apt/lists/*; \
    elif command -v yum >/dev/null 2>&1; then \
      yum install -y postgresql ca-certificates; \
      yum clean all; \
    else \
      echo "No supported package manager found to install psql" >&2; \
      exit 1; \
    fi

COPY aws-rds-global-bundle.crt /usr/local/share/ca-certificates/aws-rds-global-bundle.crt
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/aws-rds-global-bundle.pem
RUN set -eux; \
    bundle="/usr/local/share/ca-certificates/aws-rds-global-bundle.crt"; \
    if [ -f "${bundle}" ]; then \
      cp "${bundle}" /etc/ssl/certs/aws-rds-global-bundle.pem; \
      if command -v awk >/dev/null 2>&1; then \
        awk 'BEGIN{c=0} /BEGIN CERTIFICATE/{c+=1} {print > ("/usr/local/share/ca-certificates/aws-rds-" c ".crt")}' "${bundle}"; \
        rm -f "${bundle}"; \
      else \
        echo "awk not found; cannot split RDS CA bundle" >&2; \
      fi; \
    fi; \
    if command -v update-ca-certificates >/dev/null 2>&1; then \
      update-ca-certificates; \
    elif command -v update-ca-trust >/dev/null 2>&1; then \
      update-ca-trust extract; \
    else \
      echo "No supported CA update tool found to load RDS CA bundle" >&2; \
    fi

# Drop privileges back to the n8n user
USER 1000:1000
