---
name: claiming-authorship
description: Use when the user wants to install the `me.sh` script at the current repo's root so they can re-author recent commits to themselves after an agent made them. Drops an executable `./me.sh` at the repo root — running it rewrites the last few commits' author and committer fields to the current git user, preserving each commit's original author date and no-op'ing on commits where both fields already match.
---

# Claiming Authorship

Drops an executable `./me.sh` at the root of the user's current repo. They run it with `./me.sh` from that repo whenever they want the last few commits re-attributed to themselves.

## What to do

If the repo already has a `./me.sh`, confirm with the user that replacing it is intended before proceeding. Then copy the plugin's canonical script into the repo root and mark it executable:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/me.sh" ./me.sh && chmod +x ./me.sh
```

## What the script does

`./me.sh` considers the last 5 commits on the current branch (or every commit if the branch is shorter), and for each commit whose author or committer email doesn't already match the current git user, amends it so both fields read as the current user while preserving the original author date. Pass `-N` to override the count (`./me.sh -10` walks back 10 commits). Commits where both fields already match pass through unchanged, so re-running is a no-op.

Why both fields: a commit amended elsewhere (e.g. inside a VM with a different git identity) keeps the original author but flips the committer to the VM's identity. github.com surfaces this as "by Alice, committed by Bob" — running me.sh on the host fixes the committer line.

Identity is normally read from `git var GIT_AUTHOR_IDENT` (the repo's `user.email` / `user.name` config, with git's login@hostname auto-derivation as the fallback). Override per-run with environment variables:

```bash
CLAIM_EMAIL=jane@doe.com CLAIM_NAME='Jane Doe' ./me.sh
```

`CLAIM_NAME` defaults to the local part of `CLAIM_EMAIL` if only the email is set. The override doesn't touch git config — the env vars are exported into the rebase only — so it's safe in throwaway environments (fresh clones without `user.email` set, scripted runs, scenarios where you want an alternate identity for one invocation). Without the env vars, the script's behavior is unchanged.

Internally it's a `git rebase <upstream> --exec '<conditional amend>'`, where `<upstream>` is `HEAD~N` or `--root` depending on branch depth. The `--exec` body passes `--no-verify` to each `git commit --amend` so pre-commit and commit-msg hooks don't fire during the rebase. The amend is metadata-only by design — re-running content-modifying hooks (e.g. a version bumper) on already-committed trees serves no purpose and risks pushing the rebased chain out of sync with later commits' expectations.

## Caveats

- **Rewrites history.** Only safe on branches that aren't yet pushed (or only pushed to personal branches nobody else tracks). Don't run on shared branches.
- **Default count is 5.** If the stretch you want to re-author is longer, pass `-N` (e.g., `./me.sh -10`). For an unknown depth, re-run instead — already-attributed commits no-op, so successive runs march the window back only as far as new unclaimed commits exist.
- **Identity defaults to `git var GIT_AUTHOR_IDENT`.** That's git's effective user identity (`user.email` / `user.name` config, with login@hostname auto-derivation as the fallback). On a fresh clone with nothing configured, the auto-derived identity wins — set `user.email` first, or pass `CLAIM_EMAIL=...` per the env-var override above. The script reads identity at rebase time; it won't prompt.
- **`CLAIM_EMAIL` is validated only for an `@`.** Anything with an at-sign is accepted; the script doesn't enforce a stricter email format. Pass nonsense and you'll get nonsense in the author column.
- **Preserves author date, not committer date.** The committer date becomes the rewrite time — expected for any `git rebase`. If the user cares about committer date too, they'd need a different tool.
