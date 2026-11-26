#!/bin/sh
# Starts the forum (chapter 11, tier 3): installs Flarum into an empty database the first time, then on every
# start puts the settings from the environment in place, runs any new migrations and starts Apache.
set -eu
cd /var/www/flarum

for i in $(seq 60); do php forum-settings.php installed 2>/dev/null && break; [ $? -eq 1 ] && break; sleep 2; done

if ! php forum-settings.php installed; then
  echo "forum: first start, installing Flarum"
  pw=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
  # The installer's administrator gets a random password nobody keeps: the forum's password sign-in is closed,
  # and the person with ADMIN_EMAIL gets in through Authentik.
  ADMIN_PW=$pw php -r 'echo json_encode(["debug" => false, "baseUrl" => getenv("FORUM_URL"),
    "databaseConfiguration" => ["driver" => "mysql", "host" => getenv("DB_HOST"), "database" => getenv("DB_NAME"),
      "username" => getenv("DB_USER"), "password" => getenv("DB_PASSWORD"), "prefix" => ""],
    "adminUser" => ["username" => "admin", "password" => getenv("ADMIN_PW"), "password_confirmation" => getenv("ADMIN_PW"),
      "email" => getenv("ADMIN_EMAIL")],
    "settings" => ["forum_title" => getenv("FORUM_TITLE") ?: "Forum"]]);' > /tmp/install.json
  rm -f config.php
  php flarum install --file=/tmp/install.json --config=/tmp/install-config.php
  rm -f /tmp/install.json /tmp/install-config.php
fi
cp /usr/local/share/forum/config.php config.php

php forum-settings.php apply
php flarum migrate
php flarum cache:clear
php flarum assets:publish >/dev/null
chown -R www-data: storage public/assets
exec apache2-foreground
