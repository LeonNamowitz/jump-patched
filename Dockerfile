# Build Jump directly from this fork; do not reuse obsolete PHP 8.1 layers.
FROM composer:2 AS composer-bin
FROM php:8.3-fpm-alpine

# The October 2026 critical PHP fixes are present from 8.3.36 onwards.
# Refuse builds using a stale official Docker tag.
RUN php -r 'if (PHP_VERSION_ID < 80336 || PHP_VERSION_ID >= 80400) { fwrite(STDERR, "PHP 8.3.36+ required; found " . PHP_VERSION . "\n"); exit(1); }'

RUN set -eux; \
    apk add --no-cache bash curl nginx git unzip ca-certificates libxml2; \
    apk add --no-cache --virtual .jump-build-deps $PHPIZE_DEPS curl-dev libxml2-dev; \
    docker-php-ext-install -j"$(nproc)" curl dom opcache simplexml xml xmlreader xmlwriter; \
    apk del .jump-build-deps

RUN addgroup -S jumpapp && adduser -S -D -H -G jumpapp jumpapp

# Use Composer with exactly the PHP version the application runs on.
COPY --from=composer-bin /usr/bin/composer /usr/local/bin/composer
WORKDIR /usr/src/jumpapp
COPY jumpapp/ /usr/src/jumpapp/
RUN COMPOSER_ALLOW_SUPERUSER=1 composer install \
    --no-dev --optimize-autoloader --no-interaction --no-progress --prefer-dist

# Preserve the original nginx configuration, volumes and Unix socket.
COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/fpm-pool.conf /usr/local/etc/php-fpm.d/zzzz-jump.conf
COPY docker/php.ini /usr/local/etc/php/conf.d/99-jump.ini
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN set -eux; \
    cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; \
    chmod +x /usr/local/bin/entrypoint.sh; \
    mkdir -p /var/www/html /var/www/cache; \
    chown -R jumpapp:jumpapp /var/www/html /var/www/cache /usr/src/jumpapp; \
    php -l /usr/src/jumpapp/classes/Site.php; \
    php -l /usr/src/jumpapp/classes/Status.php; \
    php -l /usr/src/jumpapp/classes/Pages/AbstractPage.php; \
    php -l /usr/src/jumpapp/classes/Pages/TagPage.php; \
    php -r 'foreach (["curl", "dom", "fileinfo", "openssl", "session", "simplexml", "xml", "xmlreader", "xmlwriter", "zlib"] as $ext) { if (!extension_loaded($ext)) { fwrite(STDERR, "Missing extension: $ext\n"); exit(1); } }'

WORKDIR /var/www/html
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
HEALTHCHECK --timeout=10s CMD curl --silent --fail http://127.0.0.1:8080/fpm-ping || exit 1
