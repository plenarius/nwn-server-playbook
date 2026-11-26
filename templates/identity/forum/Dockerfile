# The forum (chapter 11, tier 3): Flarum 2 with an OpenID Connect extension, so the only way in is your Authentik.
# Coolify builds this from the forum folder of your identity repository. Pin both versions; an upgrade is its own
# pull request. PHP gets 512 MB: Flarum's style compiler runs out in the default 128 MB.
FROM php:8.4-apache
RUN apt-get update && apt-get install -y --no-install-recommends \
      libpng-dev libjpeg62-turbo-dev libfreetype-dev libicu-dev libzip-dev unzip git \
 && docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" gd pdo_mysql intl zip exif \
 && a2enmod rewrite headers remoteip \
 && echo 'memory_limit = 512M' > /usr/local/etc/php/conf.d/forum.ini \
 && rm -rf /var/lib/apt/lists/*
COPY --from=composer:2.8 /usr/bin/composer /usr/bin/composer
WORKDIR /var/www/flarum
RUN composer create-project --no-interaction --no-dev flarum/flarum:2.0.0 . \
 && composer require --no-interaction --update-no-dev flarum/core:2.0.2 floxum/flarum-ext-oidc:2.1 \
 && composer clear-cache
ENV APACHE_DOCUMENT_ROOT=/var/www/flarum/public
RUN sed -ri 's!/var/www/html!/var/www/flarum/public!g' /etc/apache2/sites-available/*.conf \
 && sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
COPY apache-proxy.conf /etc/apache2/conf-enabled/proxy.conf
COPY extend.php sso.php forum-settings.php ./
COPY config.php /usr/local/share/forum/config.php
COPY start.sh /usr/local/bin/forum-start
RUN chown -R www-data: /var/www/flarum
CMD ["forum-start"]
