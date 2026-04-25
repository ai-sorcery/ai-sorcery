---
name: claiming-authorship
description: Use when the user wants to install the `me.sh` script at the current repo's root so they can re-author recent commits to themselves after an agent made them. Drops an executable `./me.sh` at the repo root — running it rewrites the last few commits' author field to the current git user, preserving each commit's original author date and no-op'ing on anything already attributed.
---

# Claiming Authorship

Drops an executable `./me.sh` at the root of the user's current repo. They run it with `./me.sh` from that repo whenever they want the last few commits re-attributed to themselves.

## What to do

If the repo already has a `./me.sh`, confirm with the user that replacing it is intended before proceeding. Then copy the plugin's canonical script into the repo root and mark it executable:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/me.sh" ./me.sh && chmod +x ./me.sh
```

## What the script does

`./me.sh` considers the last 5 commits on the current branch (or every commit if the branch is shorter), and for each whose author email doesn't already match the current git user, amends it to reset the author to the current user while preserving the original author date. Pass `-N` to override the count (`./me.sh -10` walks back 10 commits). Commits already attributed to the user pass through unchanged, so re-running is a no-op.

Internally it's a `git rebase <upstream> --exec '<conditional amend>'`, where `<upstream>` is `HEAD~N` or `--root` depending on branch depth.

## Caveats

- **Rewrites history.** Only safe on branches that aren't yet pushed (or only pushed to personal branches nobody else tracks). Don't run on shared branches.
- **Default count is 5.** If the stretch you want to re-author is longer, pass `-N` (e.g., `./me.sh -10`). For an unknown depth, re-run instead — already-attributed commits no-op, so successive runs march the window back only as far as new unclaimed commits exist.
- **`git var GIT_AUTHOR_IDENT` determines "me."** If the user's git config varies across repos (different email per repo), make sure `git config user.email` in the current repo already reflects the identity they want to claim as, before running. The script reads the config at rebase time; it won't prompt.
- **Preserves author date, not committer date.** The committer date becomes the rewrite time — expected for any `git rebase`. If the user cares about committer date too, they'd need a different tool.
