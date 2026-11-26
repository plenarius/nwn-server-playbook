#!/usr/bin/env python3
"""Cancels queued Coolify deploys that a newer queued deploy of the same application makes pointless.

Every merge sends a webhook, and Coolify queues one deploy per merge. When merges come close together, the
older queued deploys build commits that are out of date before their turn comes: the newest commit holds
everything the older ones did. This cancels them, so only the newest is built.

It only ever cancels a deploy that is:
  - queued, never one that is running;
  - started by a push webhook, not by hand, through the API, as a forced rebuild, a rollback or a restart;
  - for the application's own branch, not a pull request preview;
  - older than another deploy of the same kind, queued for the same application.

Settings, from the environment: COOLIFY_URL (default http://127.0.0.1:8000) and COOLIFY_TOKEN, a token with
only the "read" and "deploy" permissions. --dry-run says what it would cancel and cancels nothing.
Run every 20 seconds by skip-superseded.timer. Prints a line only when it cancels something, or on an error.
"""

import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ.get("COOLIFY_URL", "http://127.0.0.1:8000").rstrip("/")
TOKEN = os.environ.get("COOLIFY_TOKEN", "")
DRY_RUN = "--dry-run" in sys.argv[1:]


def call(method, path):
    request = urllib.request.Request(
        URL + "/api/v1" + path,
        method=method,
        headers={"Authorization": "Bearer " + TOKEN, "Accept": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def may_cancel(deploy):
    return (
        deploy.get("status") == "queued"
        and bool(deploy.get("is_webhook"))
        and not deploy.get("is_api")
        and not deploy.get("force_rebuild")
        and not deploy.get("rollback")
        and not deploy.get("restart_only")
        and int(deploy.get("pull_request_id") or 0) == 0
    )


def main():
    if not TOKEN:
        print("COOLIFY_TOKEN is not set", file=sys.stderr)
        return 2
    try:
        deploys = call("GET", "/deployments")  # the queued and running deploys of every application
    except (urllib.error.URLError, TimeoutError, ValueError) as error:
        print("can't read Coolify's deploy queue: %s" % error, file=sys.stderr)
        return 1
    if isinstance(deploys, dict):  # Coolify 4.7.5 sends {"<id>": deploy, ...} once the list isn't in order
        deploys = list(deploys.values())

    queued = {}
    for deploy in deploys:
        if may_cancel(deploy):
            queued.setdefault(deploy["application_id"], []).append(deploy)

    failures = 0
    for same_app in queued.values():
        same_app.sort(key=lambda deploy: deploy["id"])
        newest = same_app[-1]
        for deploy in same_app[:-1]:
            what = "%s %s, queued %s, superseded by %s" % (
                deploy.get("application_name"), str(deploy.get("commit"))[:7],
                deploy.get("created_at"), str(newest.get("commit"))[:7])
            if DRY_RUN:
                print("would cancel " + what)
                continue
            try:
                call("POST", "/deployments/%s/cancel" % deploy["deployment_uuid"])
                print("cancelled " + what)
            except urllib.error.HTTPError as error:
                if error.code != 400:  # 400: it started or finished meanwhile, which is fine
                    failures += 1
                    print("couldn't cancel %s: HTTP %s" % (what, error.code), file=sys.stderr)
            except (urllib.error.URLError, TimeoutError) as error:
                failures += 1
                print("couldn't cancel %s: %s" % (what, error), file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
