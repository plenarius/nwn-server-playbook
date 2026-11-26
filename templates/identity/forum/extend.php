<?php
// The forum's own extensions (chapter 11, tier 3): the sign-in rules in sso.php, and the header the website,
// forum and wiki share. The header is fetched from the website (SITE_URL/embed/header.html) and kept for ten
// minutes, so a change to it on the website shows here without a forum deploy.
require_once __DIR__ . '/sso.php';

use Flarum\Extend;
use Flarum\Frontend\Document;
use Flarum\Http\RequestUtil;
use Illuminate\Contracts\Cache\Repository as Cache;
use Psr\Http\Message\ServerRequestInterface as Request;

return [
    (new Extend\Middleware('forum'))->add(MyWorld\Forum\Sso::class),

    (new Extend\Frontend('forum'))->content(function (Document $document, Request $request) {
        $site = rtrim(getenv('SITE_URL'), '/');
        $cache = resolve(Cache::class);
        $html = $cache->get('shell-header');
        if ($html === null) {
            // A User-Agent, because Cloudflare turns away requests without one.
            $got = @file_get_contents($site . '/embed/header.html', false, stream_context_create(['http' => [
                'timeout' => 5, 'header' => "User-Agent: forum-shell-header\r\n"]]));
            $html = $got === false ? '' : $got;
            // Keep it ten minutes; a failure only one, so the header comes back soon after the website does.
            $cache->put('shell-header', $html, $got === false ? 60 : 600);
        }
        if ($html === '') return;   // the website is down: the forum still works, without the shared header

        $actor = RequestUtil::getActor($request);
        $e = fn ($s) => htmlspecialchars((string) $s, ENT_QUOTES);
        $here = $request->getUri()->getPath();
        $user = $actor->isGuest()
            ? '<a href="/auth/oidc?provider=authentik&amp;returnTo=' . $e(rawurlencode($here)) . '">Sign in</a>'
            // Flarum signs out only on a POST that carries the session's token, so "Sign out" is a little form.
            : $e($actor->display_name) . ' · <form method="post" action="/logout"><input type="hidden" name="csrfToken" value="'
              . $e($request->getAttribute('session')->token()) . '"><button type="submit">Sign out</button></form>';

        $document->head[] = '<link rel="stylesheet" href="' . $e($site) . '/embed/shell.css">';
        // Flarum's own bar is fixed to the top of the window: move it down by the shared header's height, and hide
        // its own sign-in and sign-up buttons (the shared header has "Sign in").
        $document->head[] = '<style>.shell{position:fixed;top:0;left:0;right:0;height:3rem;flex-wrap:nowrap;overflow:hidden}'
            . '#header,.App-header{top:3rem!important}.App{padding-top:calc(var(--header-height) + 3rem)!important}'
            . '#drawer,#app-navigation,.App-backControl,.App-primaryControl,.App-titleControl{top:3rem!important}.item-signUp,.item-logIn{display:none!important}'
            // On a phone the forum's own bar has the room it needs only if the shared header keeps to one line.
            . '@media (max-width:767px){.shell .shell-nav{display:none}.shell .shell-name{margin-right:auto}}</style>';
        $document->foot[] = str_replace('<!--shell-user-->', $user, $html);
    }),
];
