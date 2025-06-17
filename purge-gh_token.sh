#!/usr/bin/env bash
# purge-gh_token.sh  <git-remote-url>
set -euo pipefail
REMOTE="${1:?Usage: $0 <git-remote-url>}"

# 1. clone bare mirror
WORKDIR="$(mktemp -d)"
echo "▶ Cloning bare mirror to $WORKDIR"
git clone --mirror "$REMOTE" "$WORKDIR/repo.git"

# 2. ensure git-filter-repo
if ! command -v git-filter-repo >/dev/null 2>&1; then
  echo "▶ Installing git-filter-repo with pip3 --user"
  python3 -m pip install --quiet --user git-filter-repo
  export PATH="$HOME/.local/bin:$PATH"
fi

cd "$WORKDIR/repo.git"

# 3. rewrite history
echo "▶ Rewriting history – scrubbing gh_token"
git filter-repo \
  --replace-text <(printf 'gh_token==REMOVED_SECRET\n') \
  --commit-callback '
        target = b"2f5217e1335004d6889abdef3ef0b8d370fd84bd"
        if commit.original_id == target:
            commit.message += b"\n\n[token removed]"
  '  --force

# 4. re-add origin and push
git remote add origin "$REMOTE"
echo "▶ Force-pushing cleaned history"
git push --force --all
git push --force --tags

echo "✓ Done – gh_token removed.  Rotate the token on GitHub if you haven’t already."
