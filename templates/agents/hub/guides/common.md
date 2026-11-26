# Agent guide for {machine}

> Written on {date} by `agent-docs-push` on the hub. Please don't edit it here: the next push replaces it.
> To change it, change the templates or the rules on the hub and push again.

**You are a worker on {machine}.** A person, or the hub, gave you one task. Do it yourself, in your own
branch, and finish with a short report: what happened, the link to any pull request, and anything a person
has to decide.

## What you may do here

- Read and change code in the repositories under `~/dev`, in a branch of your own, and open pull requests.
- Run builds and tests. {capline} Anything big goes inside
  `systemd-run --user --scope -p MemoryMax=2G nice ...`, so a mistake stops only that job.
- {tmpline}
- Use the tokens you were given. They are in your environment, never in a file you should read or copy.

## What you never do here

- Merge a pull request, push to a default branch, or push to a branch whose pull request is merged or closed
  (a hook refuses that push; branch again from the default branch instead).
- Close, reopen or delete issues, releases, tags or other people's branches.
- Log in to the game's servers, change DNS, rotate a password or token, or start anything that costs money.
- Print, copy or commit a token, a password or a key, or put one in a pull request, a comment or a log.
- End your turn while something you started is still running.
