#!/bin/sh
# Starts the wiki (chapter 11, tier 3): creates MediaWiki's tables in an empty database the first time, then on
# every start runs any schema updates and starts Apache. The settings are LocalSettings.php, read from the
# environment, so nothing secret is in the image.
set -eu
cd /var/www/html
db='mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT); $d = new mysqli(getenv("DB_HOST"), getenv("DB_USER"), getenv("DB_PASSWORD"), getenv("DB_NAME"));'
for i in $(seq 60); do php -r "$db" 2>/dev/null && break; sleep 2; done

if ! php -r "$db"' exit($d->query("SHOW TABLES LIKE \"page\"")->num_rows ? 0 : 1);'; then
  echo "wiki: first start, creating the tables"
  # The installer wants an administrator with a password; it gets a random one nobody keeps. People sign in
  # through Authentik, and your team group becomes the wiki's administrators (LocalSettings.php).
  pw=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
  mv LocalSettings.php /tmp/ours.php; mkdir -p /tmp/installer
  php maintenance/run.php install --dbtype=mysql --dbserver="$DB_HOST" --dbname="$DB_NAME" --dbuser="$DB_USER" \
    --dbpass="$DB_PASSWORD" --server="$WIKI_URL" --scriptpath="" --pass="$pw" --confpath=/tmp/installer "${WIKI_NAME:-My World wiki}" Installer >/dev/null
  rm -rf /tmp/installer; mv /tmp/ours.php LocalSettings.php
fi
php maintenance/run.php update --quick >/dev/null
exec apache2-foreground
