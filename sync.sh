#!/usr/bin/env bash
# Mirror /workspace/data <-> private GitHub repo $GH_DATA_REPO.
#   gpu-box-sync once   # clone-or-pull, then commit+push everything
#   gpu-box-sync loop   # same, every $SYNC_INTERVAL seconds
# Files > 90 MB (adapters, GGUFs) can't live in git → uploaded to the
# GitHub Release tagged "outputs" on the same repo (gh release upload --clobber).
set -uo pipefail
DATA=/workspace/data
REPO=${GH_DATA_REPO:-Arety30/gpu-box-data}
BIG=90M
log(){ printf '[sync %s] %s\n' "$(date +%H:%M:%S)" "$*"; }
[ -f /workspace/secrets.env ] && { set -a; . /workspace/secrets.env; set +a; }
[ -n "${GH_TOKEN:-}" ] || { log "GH_TOKEN not set"; exit 1; }
export GH_TOKEN
git config --global user.name  "gpu-box"
git config --global user.email "gpu-box@arety.cloud"
git config --global --add safe.directory "$DATA"
gh auth setup-git >/dev/null 2>&1 || true

ensure_clone(){
  if [ ! -d "$DATA/.git" ]; then
    log "cloning $REPO"
    gh repo clone "$REPO" "$DATA" -- --quiet || { log "clone failed"; return 1; }
  fi
  gh release view outputs -R "$REPO" >/dev/null 2>&1 \
    || gh release create outputs -R "$REPO" --title "gpu-box outputs" --notes "large files synced from the box" >/dev/null 2>&1
}

sync_once(){
  ensure_clone || return 1
  cd "$DATA" || return 1
  # big files: exclude from git, ship to the release
  find . -path ./.git -prune -o -type f -size +$BIG -print | sed 's|^\./||' | while read -r f; do
    grep -qxF "$f" .git/info/exclude || echo "$f" >> .git/info/exclude
    cur=$(stat -c %s "$f"); prev=$(cat ".git/.uploaded-$(echo "$f" | tr / _)" 2>/dev/null || echo 0)
    if [ "$cur" != "$prev" ]; then
      log "uploading big file to release: $f ($((cur/1048576)) MB)"
      name=$(echo "$f" | tr / __)
      cp -f "$f" "/tmp/$name" && gh release upload outputs "/tmp/$name" -R "$REPO" --clobber >/dev/null && echo "$cur" > ".git/.uploaded-$(echo "$f" | tr / _)"
      rm -f "/tmp/$name"
    fi
  done
  git add -A >/dev/null 2>&1
  if ! git diff --cached --quiet; then
    git commit -qm "gpu-box sync $(date -u +%FT%TZ) [$(hostname)]" >/dev/null
  fi
  git pull -q --rebase --autostash origin HEAD >/dev/null 2>&1 || true
  git push -q origin HEAD >/dev/null 2>&1 && log "pushed $(git rev-parse --short HEAD)" || log "push failed"
}

case "${1:-once}" in
  once) sync_once ;;
  loop) while true; do sync_once; sleep "${SYNC_INTERVAL:-120}"; done ;;
  *) echo "usage: gpu-box-sync once|loop"; exit 2 ;;
esac
