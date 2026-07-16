FROM nginx:1.25-alpine

ARG APPLY_SULU_ADMIN_THEME_PATCH=true
ARG THEME_BG_HEX=0b1020
ARG THEME_ACCENT_HEX=7c3aed
ARG OLD_ADMIN_BG_HEX=112a46
ARG OLD_ADMIN_ACCENT_HEX=52b6ca

COPY nginx/default.conf /etc/nginx/conf.d/default.conf

COPY source/public/ /var/www/html/public/

RUN set -eux; \
    manifest=/var/www/html/public/build/admin/manifest.json; \
    if [ -f "${manifest}" ]; then \
      main_js_rel="$(sed -n 's/.*\"main.js\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p' "${manifest}" | head -n 1)"; \
      main_css_rel="$(sed -n 's/.*\"main.css\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p' "${manifest}" | head -n 1)"; \
      if [ -n "${main_js_rel}" ] && [ -f "/var/www/html/public${main_js_rel}" ]; then \
        cp "/var/www/html/public${main_js_rel}" /var/www/html/public/build/admin/main.compat.js; \
      fi; \
      if [ -n "${main_css_rel}" ] && [ -f "/var/www/html/public${main_css_rel}" ]; then \
        cp "/var/www/html/public${main_css_rel}" /var/www/html/public/build/admin/main.compat.css; \
      fi; \
    fi; \
    if [ "${APPLY_SULU_ADMIN_THEME_PATCH}" = "true" ] && [ -f "${manifest}" ]; then \
      css_rel="$(sed -n 's/.*\"main.css\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p' "${manifest}" | head -n 1)"; \
      if [ -n "${css_rel}" ] && [ -f "/var/www/html/public${css_rel}" ]; then \
        css_path="/var/www/html/public${css_rel}"; \
        old_bg="#${OLD_ADMIN_BG_HEX}"; old_accent="#${OLD_ADMIN_ACCENT_HEX}"; \
        theme_bg="#${THEME_BG_HEX}"; theme_accent="#${THEME_ACCENT_HEX}"; \
        sed -i "s|${old_bg}|${theme_bg}|g" "${css_path}"; \
        sed -i "s|${old_accent}|${theme_accent}|g" "${css_path}"; \
        cp "${css_path}" /var/www/html/public/build/admin/main.compat.css; \
      fi; \
    fi

RUN mkdir -p /var/www/html/public/uploads/media \
    && chown -R 101:101 /var/www/html
