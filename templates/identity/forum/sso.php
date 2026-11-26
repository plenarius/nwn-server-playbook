<?php
// What the forum adds to its OpenID Connect extension (chapter 11, tier 3), so it behaves like the website:
//   - the forum's own password sign-in and password sign-up are closed: Authentik is the only way in;
//   - signing in here sets the shared sign-in marker, signing out here takes it away and ends the Authentik
//     session too;
//   - a page opened with the marker but no forum session tries one quiet sign-in at Authentik; a page opened
//     with a forum session but no marker (or someone else's) signs out of the forum.
// The marker is the cookie the website's auth.js describes: "sso", on your parent domain, "<sub>.<random>".
namespace MyWorld\Forum;

use Flarum\Http\CookieFactory;
use Flarum\Http\RequestUtil;
use Flarum\Http\Rememberer;
use Flarum\Http\SessionAuthenticator;
use Illuminate\Database\ConnectionInterface;
use Laminas\Diactoros\Response\RedirectResponse;
use Laminas\Diactoros\Response\TextResponse;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface as Handler;

class Sso implements MiddlewareInterface
{
    const PROVIDER = 'authentik';      // the key in forum-settings.php, and in the address Authentik sends people back to
    const MARKER = 'sso';
    const DAYS = 14;

    public function __construct(
        private SessionAuthenticator $authenticator,
        private Rememberer $rememberer,
        private CookieFactory $cookies,
        private ConnectionInterface $db,
    ) {}

    public function process(Request $request, Handler $handler): Response
    {
        $route = $request->getAttribute('routeName');
        $query = $request->getQueryParams();
        $marker = $request->getCookieParams()[self::MARKER] ?? '';

        // Password sign-in, and sign-up without the token Authentik's sign-in hands over: closed.
        if ($route === 'login' || ($route === 'register' && empty(($request->getParsedBody() ?? [])['token']))) {
            return new TextResponse('Please sign in with your account.', 403);
        }

        if ($route === 'auth.oidc') {
            $session = $request->getAttribute('session');
            // The answer to a quiet try: "not signed in at Authentik". Stay a guest, on the page they wanted.
            if (isset($query['error'])) {
                $back = $session->get('oidc_return_to') ?: '/';
                foreach (['oidc_state', 'oidc_nonce', 'oidc_pkce', 'oidc_provider', 'oidc_return_to'] as $k) $session->remove($k);
                return new RedirectResponse($back);
            }
            $response = $handler->handle($request);
            if (!isset($query['code'])) {
                // On the way out to Authentik. A quiet try asks Authentik not to show any page.
                if (!empty($query['quiet'])) {
                    $response = $response->withHeader('Location', $response->getHeaderLine('Location') . '&prompt=none')
                        ->withAddedHeader('Set-Cookie', $this->cookie('sso_tried', $marker, null, 3600));
                }
                return $response;
            }
            // Back from Authentik, signed in (or about to finish signing up): set the marker for the other sites.
            $sub = $this->subFromResponse($response);
            if ($sub && explode('.', $marker)[0] !== $sub) {
                $response = $response->withAddedHeader('Set-Cookie',
                    $this->cookie(self::MARKER, $sub . '.' . bin2hex(random_bytes(8)), getenv('SSO_COOKIE_DOMAIN'), self::DAYS * 86400));
            }
            return $response;
        }

        if ($route === 'logout') {
            $response = $handler->handle($request);
            if ($response->getStatusCode() !== 302) return $response;
            // Out of the forum, take the marker away, and end the Authentik session as well.
            // Authentik's sign-out flow (blueprint 10-sites.yaml) ends on the website's front page.
            $end = rtrim(getenv('AUTH_ISSUER'), '/') . '/end-session/';
            return $response->withHeader('Location', $end)
                ->withAddedHeader('Set-Cookie', $this->cookie(self::MARKER, '', getenv('SSO_COOKIE_DOMAIN'), 0))
                ->withAddedHeader('Set-Cookie', $this->cookie('sso_tried', '', null, 0));
        }

        // Only a page a person opens (browsers send Sec-Fetch-Dest: document), never the forum's API calls.
        if ($request->getMethod() !== 'GET' || $request->getHeaderLine('Sec-Fetch-Dest') !== 'document') {
            return $handler->handle($request);
        }
        $actor = RequestUtil::getActor($request);
        $here = $request->getUri()->getPath() . ($request->getUri()->getQuery() !== '' ? '?' . $request->getUri()->getQuery() : '');

        if (!$actor->isGuest()) {
            $sub = $this->db->table('login_providers')->where('user_id', $actor->id)
                ->where('provider', 'oidc-' . self::PROVIDER)->value('identifier');
            if ($marker === '' || explode('.', $marker)[0] !== $sub) {
                // Signed out on another site (or someone else signed in there): sign out here, quietly.
                $this->authenticator->logOut($request->getAttribute('session'));
                return $this->rememberer->forget(new RedirectResponse($here));
            }
        } elseif ($marker !== '' && ($request->getCookieParams()['sso_tried'] ?? '') !== $marker) {
            return new RedirectResponse('/auth/oidc?' . http_build_query(['provider' => self::PROVIDER, 'quiet' => 1, 'returnTo' => $here]));
        }
        return $handler->handle($request);
    }

    // Which Authentik account the forum just signed in (a remember cookie) or is about to sign up (a sign-up token).
    private function subFromResponse(Response $response): ?string
    {
        $remember = $this->cookies->getName('remember');
        foreach ($response->getHeader('Set-Cookie') as $c) {
            if (preg_match('/^' . preg_quote($remember, '/') . '=([^;]+)/', $c, $m)) {
                $userId = $this->db->table('access_tokens')->where('token', urldecode($m[1]))->value('user_id');
                return $this->db->table('login_providers')->where('user_id', $userId)
                    ->where('provider', 'oidc-' . self::PROVIDER)->value('identifier');
            }
        }
        if (preg_match('/[?&]_flarum_auth=([^&]+)/', $response->getHeaderLine('Location'), $m)) {
            return $this->db->table('registration_tokens')->where('token', urldecode($m[1]))->value('identifier');
        }
        return null;
    }

    private function cookie(string $name, string $value, ?string $domain, int $maxAge): string
    {
        return $name . '=' . $value . '; Path=/; Secure; HttpOnly; SameSite=Lax; Max-Age=' . $maxAge . ($domain ? '; Domain=' . $domain : '');
    }
}
