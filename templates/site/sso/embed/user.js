// Fills the shared header's user area on the website itself: "Sign in", or the member's name and "Sign out".
(function () {
  var el = document.querySelector('.shell-user');
  if (!el) return;
  var here = encodeURIComponent(location.pathname + location.search);
  fetch('/auth/me', { credentials: 'same-origin' }).then(function (r) { return r.json(); }).then(function (me) {
    el.textContent = '';
    var a = document.createElement('a');
    if (me.signedIn) {
      var who = document.createElement('a');
      who.href = '/account'; who.textContent = me.name;
      el.appendChild(who); el.appendChild(document.createTextNode(' · '));
      a.href = '/auth/logout'; a.textContent = 'Sign out';
    } else {
      a.href = '/auth/login?returnTo=' + here; a.textContent = 'Sign in';
    }
    el.appendChild(a);
  }).catch(function () {});
})();
