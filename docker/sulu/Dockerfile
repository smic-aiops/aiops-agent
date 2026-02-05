ARG SULU_VERSION=3.0.3
ARG PHP_IMAGE=php:8.4-fpm
ARG PHP_CLI_IMAGE=php:8.4-cli
ARG COMMON_PACKAGES="ca-certificates git curl unzip zip libpq-dev libzip-dev libicu-dev libonig-dev libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev gnupg libvips-dev libffi-dev pkg-config build-essential autoconf"
ARG NODE_SETUP_SCRIPT=https://deb.nodesource.com/setup_20.x

FROM ${PHP_CLI_IMAGE} AS composer
ARG COMMON_PACKAGES
ARG NODE_SETUP_SCRIPT
RUN set -eux;     mkdir -p /etc/apt;     codename="$(. /etc/os-release && echo \"${VERSION_CODENAME:-bookworm}\")";     if [ ! -f /etc/apt/sources.list ]; then       echo "deb https://deb.debian.org/debian ${codename} main" > /etc/apt/sources.list;       echo "deb https://deb.debian.org/debian ${codename}-updates main" >> /etc/apt/sources.list;       echo "deb https://security.debian.org/debian-security ${codename}-security main" >> /etc/apt/sources.list;     else       sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list;       sed -i 's|http://security.debian.org|https://security.debian.org|g' /etc/apt/sources.list;     fi;     apt-get update;     apt-get install -y --no-install-recommends ${COMMON_PACKAGES};     curl -fsSL ${NODE_SETUP_SCRIPT} | bash -;     apt-get install -y --no-install-recommends nodejs;     npm install -g yarn@1.22.19;     curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer;     printf "\n" | pecl install vips;     docker-php-ext-enable vips;     docker-php-ext-configure ffi --with-ffi;     docker-php-ext-configure intl;     docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp;     docker-php-ext-install intl gd pdo pdo_pgsql zip ffi;     rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY source/ /app/
# Guard against Docker layer cache surprises: ensure our AIOps seed files are present in the image.
COPY source/content/pages.json /app/content/pages.json
COPY source/bin/replace_sulu_pages.php /app/bin/replace_sulu_pages.php
COPY init-db.sh /app/docker/init-db.sh
COPY init-db.php /app/docker/init-db.php
ENV COMPOSER_ALLOW_SUPERUSER=1
ENV COMPOSER_MEMORY_LIMIT=-1
RUN composer install --no-dev --no-interaction --prefer-dist --classmap-authoritative --no-progress

FROM ${PHP_IMAGE} AS runtime
ARG SULU_VERSION
ARG COMMON_PACKAGES
ARG NODE_SETUP_SCRIPT
ARG APPLY_SULU_ADMIN_THEME_PATCH=true
ARG THEME_BG_HEX=0b1020
ARG THEME_ACCENT_HEX=7c3aed
ARG OLD_ADMIN_BG_HEX=112a46
ARG OLD_ADMIN_ACCENT_HEX=52b6ca
RUN set -eux;     mkdir -p /etc/apt;     codename="$(. /etc/os-release && echo \"${VERSION_CODENAME:-bookworm}\")";     if [ ! -f /etc/apt/sources.list ]; then       echo "deb https://deb.debian.org/debian ${codename} main" > /etc/apt/sources.list;       echo "deb https://deb.debian.org/debian ${codename}-updates main" >> /etc/apt/sources.list;       echo "deb https://security.debian.org/debian-security ${codename}-security main" >> /etc/apt/sources.list;     else       sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list;       sed -i 's|http://security.debian.org|https://security.debian.org|g' /etc/apt/sources.list;     fi;     apt-get update;     apt-get install -y --no-install-recommends ${COMMON_PACKAGES};     curl -fsSL ${NODE_SETUP_SCRIPT} | bash -;     apt-get install -y --no-install-recommends nodejs;     npm install -g yarn@1.22.19;     printf "\n" | pecl install vips;     docker-php-ext-enable vips;     docker-php-ext-configure ffi --with-ffi;     docker-php-ext-configure intl;     docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp;     docker-php-ext-install intl gd pdo pdo_pgsql zip ffi;     rm -rf /var/lib/apt/lists/*
WORKDIR /var/www/html
COPY --from=composer /app /var/www/html
COPY --chown=www-data:www-data config/ config/
COPY --chown=www-data:www-data hooks/ hooks/
RUN set -eux; \
    if [ "${APPLY_SULU_ADMIN_THEME_PATCH}" = "true" ] && [ -f public/build/admin/manifest.json ]; then \
      css_rel="$(php -r '$m=json_decode(@file_get_contents("public/build/admin/manifest.json"), true); echo is_array($m)&&isset($m["main.css"])?$m["main.css"]:"";')"; \
      if [ -n "${css_rel}" ] && [ -f "public${css_rel}" ]; then \
        css_path="public${css_rel}"; \
        old_bg="#${OLD_ADMIN_BG_HEX}"; old_accent="#${OLD_ADMIN_ACCENT_HEX}"; \
        theme_bg="#${THEME_BG_HEX}"; theme_accent="#${THEME_ACCENT_HEX}"; \
        sed -i "s|${old_bg}|${theme_bg}|g" "${css_path}"; \
        sed -i "s|${old_accent}|${theme_accent}|g" "${css_path}"; \
      fi; \
    fi
RUN set -eux;     chown -R www-data:www-data /var/www/html
RUN chmod +x /var/www/html/hooks/onready/*.sh
RUN chmod +x /var/www/html/docker/init-db.sh
LABEL org.opencontainers.image.title="Sulu PHP"       org.opencontainers.image.version="3.0.3"       org.opencontainers.image.vendor="aiops-agent"       org.opencontainers.image.source="https://github.com/sulu/skeleton"
USER www-data
