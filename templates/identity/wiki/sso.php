<?php
// What the wiki adds to PluggableAuth (chapter 11, tier 3), so it behaves like the website and the forum:
//   - signing in here sets the shared sign-in marker, signing out here takes it away and ends the Authentik
//     session too (Authentik's sign-out flow then lands on the website's front page);
//   - a page opened with the marker but no wiki session tries one quiet sign-in at Authentik; a page opened with
//     a wiki session but no marker (or someone else's) signs out of the wiki;
//   - the header the three sites share, fetched from the website and kept for ten minutes.
// The marker is the cookie the website's auth.js describes: "sso", on your parent domain, "<sub>.<random>".
if ( !defined( 'MEDIAWIKI' ) ) exit;

function ssoCookie( string $name, string $value, int $maxAge, bool $shared = false ): void {
	header( 'Set-Cookie: ' . $name . '=' . $value . '; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=' . $maxAge
		. ( $shared ? '; Domain=' . getenv( 'SSO_COOKIE_DOMAIN' ) : '' ), false );
}

function ssoSubject( int $userId ): ?string {
	$db = MediaWiki\MediaWikiServices::getInstance()->getConnectionProvider()->getReplicaDatabase();
	$sub = $db->newSelectQueryBuilder()->select( 'oidc_subject' )->from( 'openid_connect' )
		->where( [ 'oidc_user' => $userId ] )->caller( __FUNCTION__ )->fetchField();
	return $sub === false ? null : $sub;
}

// Quiet tries carry a two-minute cookie through MediaWiki's sign-in pages. Ask Authentik not to show a page, and
// if it answers "not signed in", go back to the page they wanted as a guest instead of showing an error.
if ( ( $_COOKIE['sso_quiet'] ?? '' ) === '1' ) {
	$wgPluggableAuth_Config['Authentik']['data']['authparam'] = [ 'prompt' => 'none' ];
}
if ( isset( $_GET['error'] ) && str_contains( $_SERVER['REQUEST_URI'] ?? '', 'PluggableAuthLogin' ) ) {
	$back = $_COOKIE['sso_back'] ?? '';
	ssoCookie( 'sso_back', '', 0 );
	ssoCookie( 'sso_quiet', '', 0 );
	header( 'Location: ' . $wgServer . ( preg_match( '#^/(?![/\\\\])#', $back ) ? $back : '/' ) );
	exit;
}

$wgHooks['BeforeInitialize'][] = static function ( $title, $unused, $output, $user, $request, $mw ) {
	if ( $request->getMethod() !== 'GET' || $request->getHeader( 'Sec-Fetch-Dest' ) !== 'document'
		|| $title->isSpecial( 'PluggableAuthLogin' ) || $title->isSpecial( 'Userlogin' ) || $title->isSpecial( 'Userlogout' ) ) {
		return;
	}
	$marker = $_COOKIE['sso'] ?? '';
	$here = $request->getRequestURL();
	if ( $user->isRegistered() ) {
		if ( $marker === '' || explode( '.', $marker )[0] !== ssoSubject( $user->getId() ) ) {
			// Signed out on another site (or someone else signed in there): sign out here, quietly.
			$user->logout();
			$output->redirect( $here );
		}
	} elseif ( $marker !== '' && ( $_COOKIE['sso_tried'] ?? '' ) !== $marker ) {
		ssoCookie( 'sso_tried', $marker, 3600 );
		ssoCookie( 'sso_back', rawurlencode( $here ), 600 );
		ssoCookie( 'sso_quiet', '1', 120 );
		// Straight away, so no redirect of MediaWiki's own (such as / to the main page) can replace it.
		header( 'Location: ' . SpecialPage::getTitleFor( 'Userlogin' )->getFullURL( [
			'returnto' => $title->getPrefixedText() ] ), true, 302 );
		header( 'Cache-Control: no-store' );
		exit;
	}
};

// Signed in through Authentik: set the marker for the other sites.
$wgHooks['UserLoggedIn'][] = static function ( $user ) {
	$sub = ssoSubject( $user->getId() );
	if ( $sub && explode( '.', $_COOKIE['sso'] ?? '' )[0] !== $sub ) {
		ssoCookie( 'sso', $sub . '.' . bin2hex( random_bytes( 8 ) ), 14 * 86400, true );
	}
	ssoCookie( 'sso_back', '', 0 );
	ssoCookie( 'sso_quiet', '', 0 );
};

// Signed out here: take the marker away and end the Authentik session too.
$wgHooks['UserLogoutComplete'][] = static function ( $user, &$html, $oldName ) {
	ssoCookie( 'sso', '', 0, true );
	ssoCookie( 'sso_tried', '', 0 );
	RequestContext::getMain()->getOutput()->redirect( rtrim( getenv( 'AUTH_ISSUER' ), '/' ) . '/end-session/' );
};

// The shared header. Vector's own header and its sticky bar move down by its height; the wiki's own "Log in"
// link is hidden, because the shared header has "Sign in".
$wgHooks['BeforePageDisplay'][] = static function ( $out, $skin ) {
	$site = rtrim( getenv( 'SITE_URL' ), '/' );
	$out->addHeadItem( 'shell-css', '<link rel="stylesheet" href="' . htmlspecialchars( $site ) . '/embed/shell.css">'
		. '<style>.shell{position:fixed;top:0;left:0;right:0;width:auto;height:3rem;flex-wrap:nowrap;overflow:hidden}'
		. 'body{padding-top:3rem}.vector-sticky-header{top:3rem!important}#pt-login-2,#pt-login,#pt-createaccount-2{display:none!important}'
		. '@media (max-width:767px){.shell .shell-nav{display:none}}</style>' );
};
$wgHooks['SkinAfterBottomScripts'][] = static function ( $skin, &$text ) {
	$cache = MediaWiki\MediaWikiServices::getInstance()->getLocalServerObjectCache();
	$html = $cache->getWithSetCallback( $cache->makeKey( 'shell-header' ), 600, static function ( &$ttl ) {
		// A User-Agent, because Cloudflare turns away requests without one.
		$got = @file_get_contents( rtrim( getenv( 'SITE_URL' ), '/' ) . '/embed/header.html', false,
			stream_context_create( [ 'http' => [ 'timeout' => 5, 'header' => "User-Agent: wiki-shell-header\r\n" ] ] ) );
		if ( $got === false ) { $ttl = 60; return ''; }
		return $got;
	} );
	if ( $html === '' ) return;    // the website is down: the wiki still works, without the shared header
	$user = $skin->getUser();
	$title = $skin->getTitle();
	if ( $user->isRegistered() ) {
		// MediaWiki signs out only on a POST that carries the session's token, so "Sign out" is a little form.
		$who = htmlspecialchars( $user->getName() ) . ' · <form method="post" action="'
			. htmlspecialchars( SpecialPage::getTitleFor( 'UserLogout' )->getLocalURL() ) . '">'
			. '<input type="hidden" name="wpEditToken" value="' . htmlspecialchars( $user->getEditToken( 'logoutToken' ) ) . '">'
			. '<button type="submit">Sign out</button></form>';
	} else {
		$who = '<a href="' . htmlspecialchars( SpecialPage::getTitleFor( 'Userlogin' )->getLocalURL(
			[ 'returnto' => $title ? $title->getPrefixedText() : '' ] ) ) . '">Sign in</a>';
	}
	$text .= str_replace( '<!--shell-user-->', $who, $html );
};
