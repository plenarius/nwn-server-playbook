# The wiki (chapter 11, tier 3): MediaWiki 1.43, the long-term-support release, with PluggableAuth and
# OpenIDConnect so the only way in is your Authentik. Coolify builds this from the wiki folder of your identity
# repository. The two extensions are pinned to exact commits of their REL1_43 branches; an upgrade is its own
# pull request.
FROM mediawiki:1.43
ARG PLUGGABLEAUTH=620f20fef07ef9320a94a87482b3c09d03943242
ARG OPENIDCONNECT=9efcb340da38ec2186075aa8fade80baf928b09c
COPY --from=composer:2.8 /usr/bin/composer /usr/bin/composer
RUN apt-get update && apt-get install -y --no-install-recommends unzip && rm -rf /var/lib/apt/lists/* \
 && cd extensions \
 && mkdir PluggableAuth OpenIDConnect \
 && curl -fsSL https://github.com/wikimedia/mediawiki-extensions-PluggableAuth/archive/$PLUGGABLEAUTH.tar.gz | tar xz --strip-components=1 -C PluggableAuth \
 && curl -fsSL https://github.com/wikimedia/mediawiki-extensions-OpenIDConnect/archive/$OPENIDCONNECT.tar.gz | tar xz --strip-components=1 -C OpenIDConnect \
 && cd .. \
 && printf '{"extra":{"merge-plugin":{"include":["extensions/OpenIDConnect/composer.json"]}}}' > composer.local.json \
 && COMPOSER_ALLOW_SUPERUSER=1 composer update --no-dev --no-interaction --no-progress \
 && rm -rf /root/.composer /root/.cache
COPY LocalSettings.php sso.php /var/www/html/
COPY start.sh /usr/local/bin/wiki-start
CMD ["wiki-start"]
