<?php
// The wiki's settings (chapter 11, tier 3), read from the container's environment, which Coolify fills in.
// Change them here, in a pull request, like Authentik's blueprints.
if ( !defined( 'MEDIAWIKI' ) ) exit;

$wgSitename = getenv( 'WIKI_NAME' ) ?: 'My World wiki';
$wgMetaNamespace = 'Project';
$wgServer = rtrim( getenv( 'WIKI_URL' ), '/' );
$wgScriptPath = '';
$wgResourceBasePath = $wgScriptPath;
$wgLogos = [ 'icon' => "$wgResourceBasePath/resources/assets/change-your-logo.svg" ];
$wgLanguageCode = 'en';
$wgLocaltimezone = 'UTC';
$wgDefaultSkin = 'vector-2022';
wfLoadSkin( 'Vector' );

$wgDBtype = 'mysql';
$wgDBserver = getenv( 'DB_HOST' );
$wgDBname = getenv( 'DB_NAME' );
$wgDBuser = getenv( 'DB_USER' );
$wgDBpassword = getenv( 'DB_PASSWORD' );
$wgDBTableOptions = 'ENGINE=InnoDB, DEFAULT CHARSET=binary';
$wgSecretKey = getenv( 'WIKI_SECRET_KEY' );
$wgUpgradeKey = substr( hash( 'sha256', 'upgrade' . $wgSecretKey ), 0, 16 );
$wgAuthenticationTokenVersion = '1';
$wgMainCacheType = CACHE_ACCEL;
$wgSessionCacheType = CACHE_DB;
$wgEnableUploads = false;     // turn on with a volume for images/ when you want pictures
$wgUseInstantCommons = false;
$wgEnableEmail = false;       // Authentik does the mail: invitations and password resets
$wgDiff3 = '/usr/bin/diff3';
$wgShowExceptionDetails = false;
// Coolify's proxy sits in front: trust it for the visitor's address.
$wgUsePrivateIPs = true;
$wgCdnServersNoPurge = [ '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16' ];

// Who may do what: everyone reads, members edit, nobody makes an account here (Authentik does that).
$wgGroupPermissions['*']['edit'] = false;
$wgGroupPermissions['*']['createaccount'] = false;
$wgGroupPermissions['*']['autocreateaccount'] = true;
$wgGroupPermissions['user']['edit'] = true;

// Signing in through Authentik (its blueprint 10-sites.yaml has the other half). The wiki's own password form
// is off. Your "team" group in Authentik makes someone a wiki administrator, at every sign-in.
wfLoadExtension( 'PluggableAuth' );
wfLoadExtension( 'OpenIDConnect' );
$wgPluggableAuth_EnableLocalLogin = false;
$wgPluggableAuth_EnableAutoLogin = false;
$wgPluggableAuth_ButtonLabelMessage = 'pluggableauth-loginbutton-label';
$wgPluggableAuth_Config['Authentik'] = [
	'plugin' => 'OpenIDConnect',
	'data' => [
		'providerURL' => rtrim( getenv( 'AUTH_ISSUER' ), '/' ) . '/',
		'clientID' => 'wiki',
		'clientsecret' => getenv( 'WIKI_CLIENT_SECRET' ),
		'scope' => [ 'openid', 'profile', 'email' ],
		'codeChallengeMethod' => 'S256',
	],
	'groupsyncs' => [ [
		'type' => 'mapped',
		'map' => [ 'sysop' => [ 'groups' => [ 'team' ] ], 'bureaucrat' => [ 'groups' => [ 'team' ] ] ],
	] ],
];
// The shared header and the sign-in marker: sso.php.
require_once __DIR__ . '/sso.php';
