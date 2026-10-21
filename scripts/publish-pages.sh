#!/usr/bin/env bash
# Publishes one build to the GitHub Pages branch.
#
# Usage: scripts/publish-pages.sh --tag TAG --channel stable|branch --ipa PATH ... (pages_site.py "add" options)
#
# The branch is rewritten as a single orphan commit on every publish so IPAs never pile up in the
# history. Only top-level folders that contain build.json are kept (the branch may have been created
# from the source code), files are staged with `git add -A --force` so a `.gitignore` containing `*.ipa`
# cannot drop the IPA, and the push uses --force-with-lease, retrying from a fresh fetch when another
# build published at the same time.
#
# Environment: PAGES_REMOTE (default origin), PAGES_BRANCH (default gh-pages),
#              PAGES_MAX_ATTEMPTS (default 5), PAGES_RETRY_DELAY (seconds, default 5).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
remote="${PAGES_REMOTE:-origin}"
branch="${PAGES_BRANCH:-gh-pages}"
max_attempts="${PAGES_MAX_ATTEMPTS:-5}"
retry_delay="${PAGES_RETRY_DELAY:-5}"

tag=""
previous=""
for argument in "$@"; do
  if [ "$previous" = "--tag" ]; then
    tag="$argument"
  fi
  previous="$argument"
done
if [ -z "$tag" ]; then
  echo "::error::publish-pages.sh requires --tag" >&2
  exit 2
fi

export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-github-actions[bot]}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-$GIT_AUTHOR_NAME}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-$GIT_AUTHOR_EMAIL}"

git_dir="$(git rev-parse --absolute-git-dir)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for attempt in $(seq 1 "$max_attempts"); do
  echo "Publishing $tag to $branch (attempt $attempt of $max_attempts)"
  old=""
  if git --git-dir="$git_dir" fetch --quiet --no-tags --depth=1 "$remote" \
      "+refs/heads/$branch:refs/remotes/$remote/$branch" 2>/dev/null; then
    old="$(git --git-dir="$git_dir" rev-parse "refs/remotes/$remote/$branch")"
  fi

  site="$work/site"
  rm -rf "$site"
  mkdir -p "$site"
  if [ -n "$old" ]; then
    git --git-dir="$git_dir" archive "$old" | tar -x -C "$site"
  fi

  python3 "$script_dir/pages_site.py" add --site "$site" "$@"

  index_file="$work/index"
  rm -f "$index_file"
  GIT_INDEX_FILE="$index_file" git --git-dir="$git_dir" --work-tree="$site" -C "$site" add -A --force .
  tree="$(GIT_INDEX_FILE="$index_file" git --git-dir="$git_dir" write-tree)"
  commit="$(git --git-dir="$git_dir" commit-tree "$tree" -m "Publish $tag")"

  if git --git-dir="$git_dir" push --quiet "$remote" "$commit:refs/heads/$branch" \
      --force-with-lease="refs/heads/$branch:$old"; then
    echo "Published $tag to $branch as $commit"
    exit 0
  fi

  if [ "$attempt" -lt "$max_attempts" ]; then
    delay=$((retry_delay * attempt + RANDOM % 3))
    echo "Push rejected (another build probably published first); retrying in ${delay}s"
    sleep "$delay"
  fi
done

echo "::error::Could not publish $tag to $branch after $max_attempts attempts" >&2
exit 1
