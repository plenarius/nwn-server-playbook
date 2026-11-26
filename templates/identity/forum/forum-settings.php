<?php
// Small helper for start.sh (chapter 11, tier 3), so the forum's sign-in is set from the environment on every
// start, like Authentik's blueprints: change the environment in Coolify and redeploy, never the admin page.
//   php forum-settings.php installed   exit 0 when Flarum's tables exist
//   php forum-settings.php apply       write the settings below
$db = new PDO('mysql:host=' . getenv('DB_HOST') . ';dbname=' . getenv('DB_NAME') . ';charset=utf8mb4',
    getenv('DB_USER'), getenv('DB_PASSWORD'), [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

if (($argv[1] ?? '') === 'installed') {
    exit($db->query("SHOW TABLES LIKE 'settings'")->fetch() ? 0 : 1);
}

$set = $db->prepare('INSERT INTO settings (`key`, `value`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)');
$get = fn ($k) => ($r = $db->query('SELECT `value` FROM settings WHERE `key` = ' . $db->quote($k))->fetch()) ? $r[0] : null;

// Authentik as the forum's only way in. The provider id "authentik" is part of the address Authentik sends
// people back to (/auth/oidc?provider=authentik), so it has to match the blueprint.
$set->execute(['floxum-oidc.providers', json_encode(['authentik' => [
    'issuer' => rtrim(getenv('AUTH_ISSUER'), '/'),
    'client_id' => 'forum',
    'client_secret' => getenv('AUTH_CLIENT_SECRET'),
    'scope' => 'openid profile email',
    'claim_username' => 'preferred_username',
    'button_title' => 'Sign in',
    'icon' => 'fas fa-right-to-bracket',
]], JSON_UNESCAPED_SLASHES)]);
$set->execute(['forum_title', getenv('FORUM_TITLE') ?: 'Forum']);
// New accounts come only through Authentik; sso.php refuses the forum's own password sign-up and sign-in.
$set->execute(['allow_sign_up', '1']);

$enabled = json_decode($get('extensions_enabled') ?? '[]', true) ?: [];
if (!in_array('floxum-oidc', $enabled, true)) {
    $enabled[] = 'floxum-oidc';
    $set->execute(['extensions_enabled', json_encode($enabled)]);
}
echo "forum settings applied\n";
