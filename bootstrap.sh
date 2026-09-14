#!/usr/bin/env bash
# gpu-box bootstrap: runs as PID 1's child inside the container on every start.
# Idempotent — re-running after a restart only does the missing pieces.
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
WS=/workspace
DATA=$WS/data
VENV=$WS/venv
RAW=${GPU_BOX_RAW:-https://raw.githubusercontent.com/Arety30/gpu-box/main}
log(){ printf '\n\033[1;32m[gpu-box %s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }

mkdir -p "$WS" /var/run/tailscale
[ -f "$WS/secrets.env" ] && { set -a; . "$WS/secrets.env"; set +a; }

# ---------- 1. base packages (~30 s) ----------
if [ ! -f /usr/local/share/gpu-box.pkgs ]; then
  log "installing base packages"
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends \
    ca-certificates curl gnupg git git-lfs openssh-client rsync \
    python3 python3-venv python3-pip python3-dev cmake build-essential \
    tmux htop nvtop jq vim less unzip iproute2 iptables >/dev/null
  # GitHub CLI
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  # Tailscale
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
    -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
    -o /etc/apt/sources.list.d/tailscale.list
  apt-get update -qq && apt-get install -y -qq gh tailscale >/dev/null
  git lfs install --system >/dev/null
  touch /usr/local/share/gpu-box.pkgs
fi

# ---------- 2. tailscale (SSH built in) ----------
log "starting tailscaled"
tailscaled --state=/var/lib/tailscale/tailscaled.state \
           --socket=/var/run/tailscale/tailscaled.sock >/var/log/tailscaled.log 2>&1 &
sleep 2
TS_ARGS=(--ssh --hostname="${TS_HOSTNAME:-gpu-box}" --accept-dns=false)
if [ -n "${TS_AUTHKEY:-}" ]; then
  tailscale up "${TS_ARGS[@]}" --authkey="$TS_AUTHKEY" && log "tailscale up (authkey)"
else
  # No key: prints a one-time login URL. Also saved to /workspace/tailscale-login.txt
  ( tailscale up "${TS_ARGS[@]}" 2>&1 | tee "$WS/tailscale-login.txt" ) &
  sleep 4
  log "NO TS_AUTHKEY — open the login URL above (also: docker logs gpu-box | grep login.tailscale.com)"
fi

# ---------- 3. helper scripts + python env (background, ~3 min first time) ----------
curl -fsSL "$RAW/sync.sh" -o /usr/local/bin/gpu-box-sync && chmod +x /usr/local/bin/gpu-box-sync
curl -fsSL "$RAW/finetune/train.sh" -o /usr/local/bin/train && chmod +x /usr/local/bin/train
mkdir -p "$WS/finetune" && curl -fsSL "$RAW/finetune/finetune_lora.py" -o "$WS/finetune/finetune_lora.py"
if [ ! -f "$VENV/.ready" ]; then
  log "creating python venv + unsloth (background; tail /workspace/pip.log)"
  ( python3 -m venv "$VENV" \
    && "$VENV/bin/pip" install -q --upgrade pip \
    && "$VENV/bin/pip" install -q "unsloth" "datasets" "trl" "huggingface_hub" "hf_transfer" \
    && touch "$VENV/.ready" && echo "venv ready" ) >"$WS/pip.log" 2>&1 &
fi
cat > /etc/profile.d/gpu-box.sh <<'PROF'
[ -f /workspace/secrets.env ] && { set -a; . /workspace/secrets.env; set +a; }
[ -f /workspace/venv/bin/activate ] && . /workspace/venv/bin/activate
cd /workspace 2>/dev/null
alias gpus='nvidia-smi'
echo "gpu-box: data=/workspace/data (auto-synced)  train=$(command -v train)  sync now: gpu-box-sync once"
PROF
grep -q gpu-box.sh /root/.bashrc || echo '. /etc/profile.d/gpu-box.sh' >> /root/.bashrc

# ---------- 4. GitHub data sync (waits for GH_TOKEN) ----------
( while true; do
    [ -f "$WS/secrets.env" ] && { set -a; . "$WS/secrets.env"; set +a; }
    if [ -n "${GH_TOKEN:-}" ]; then
      export GH_TOKEN GH_DATA_REPO="${GH_DATA_REPO:-Arety30/gpu-box-data}"
      exec /usr/local/bin/gpu-box-sync loop
    fi
    sleep 10
  done ) &
SYNC_PID=$!

final(){ log "stopping — final sync"; kill $SYNC_PID 2>/dev/null; GH_TOKEN="${GH_TOKEN:-}" /usr/local/bin/gpu-box-sync once; exit 0; }
trap final TERM INT

nvidia-smi --query-gpu=name,memory.total --format=csv 2>/dev/null || log "nvidia-smi not available (no GPU passthrough?)"
log "READY.  ssh root@${TS_HOSTNAME:-gpu-box} (Tailscale SSH) | docker exec -it gpu-box bash"
while true; do sleep 3600 & wait $!; done
