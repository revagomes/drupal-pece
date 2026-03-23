# =============================================================================
# Builder Stage: Install dependencies and build application
# =============================================================================
FROM php:8.3-fpm-bookworm AS builder

# Install system dependencies required for Drupal and PHP extensions
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    libicu-dev \
    libpq-dev \
    libonig-dev \
    libxml2-dev \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# Configure and install PHP extensions required by Drupal
RUN apt-get update && apt-get install -y zlib1g-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    gd \
    pdo \
    pdo_mysql \
    opcache \
    intl \
    zip \
    bcmath \
    mbstring \
    xml

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy composer files first for better layer caching
COPY composer.json composer.lock ./

# Install PHP dependencies (production only, no dev dependencies)
RUN composer install \
    --no-dev \
    --optimize-autoloader \
    --no-interaction \
    --no-progress \
    --prefer-dist

# Copy application code
COPY . .

# Create required directories with proper permissions
RUN mkdir -p web/sites/default/files \
    && mkdir -p web/sites/default/files/private \
    && mkdir -p config/sync

# =============================================================================
# Production Stage: Minimal runtime image
# =============================================================================
FROM php:8.3-fpm-bookworm AS production

# Install only runtime dependencies
RUN apt-get update && apt-get install -y \
    libpng16-16 \
    libjpeg62-turbo \
    libfreetype6 \
    libzip4 \
    libicu72 \
    libpq5 \
    libonig5 \
    libxml2 \
    mariadb-client \
    libfcgi-bin \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions (same as builder)
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    gd \
    pdo \
    pdo_mysql \
    opcache \
    intl \
    zip \
    bcmath \
    mbstring \
    xml

# Configure PHP for production
RUN { \
    echo 'opcache.memory_consumption=256'; \
    echo 'opcache.interned_strings_buffer=16'; \
    echo 'opcache.max_accelerated_files=10000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=1'; \
    echo 'opcache.validate_timestamps=0'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini

# Configure PHP settings for Drupal
RUN { \
    echo 'memory_limit=512M'; \
    echo 'upload_max_filesize=128M'; \
    echo 'post_max_size=128M'; \
    echo 'max_execution_time=300'; \
    echo 'max_input_vars=3000'; \
    echo 'realpath_cache_size=4096K'; \
    echo 'realpath_cache_ttl=600'; \
    } > /usr/local/etc/php/conf.d/drupal.ini

# Configure PHP-FPM
RUN { \
    echo '[www]'; \
    echo 'pm = dynamic'; \
    echo 'pm.max_children = 50'; \
    echo 'pm.start_servers = 5'; \
    echo 'pm.min_spare_servers = 5'; \
    echo 'pm.max_spare_servers = 35'; \
    echo 'pm.max_requests = 500'; \
    echo 'pm.status_path = /fpm-status'; \
    echo 'ping.path = /fpm-ping'; \
    echo 'ping.response = pong'; \
    } > /usr/local/etc/php-fpm.d/zz-docker.conf

# Set working directory
WORKDIR /var/www/html

# Copy application and dependencies from builder
COPY --from=builder --chown=www-data:www-data /var/www/html /var/www/html

# Ensure proper permissions for Drupal directories
RUN chown -R www-data:www-data /var/www/html/web/sites/default/files \
    && chown -R www-data:www-data /var/www/html/web/sites/default/files/private \
    && chmod -R 775 /var/www/html/web/sites/default/files \
    && chmod -R 775 /var/www/html/web/sites/default/files/private

# Switch to non-root user
USER www-data

# Expose PHP-FPM port
EXPOSE 9000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD SCRIPT_NAME=/fpm-ping SCRIPT_FILENAME=/fpm-ping REQUEST_METHOD=GET \
    cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1

# Start PHP-FPM
CMD ["php-fpm"]
