# gpu-box

Throwaway GPU terminal box for **NVIDIA Brev → Docker Compose mode**.
Ubuntu 24.04 + CUDA 12.8/cuDNN, every host GPU passed through, **Tailscale SSH** inside
the container, and `/workspace/data` mirrored to a private GitHub repo every 2 minutes
(files > 90 MB go to the repo's `outputs` release).

## Deploy (Brev)
1. Software Configuration → **Docker Compose** → *Provide GitHub URL*:
   `https://github.com/Arety30/gpu-box/blob/main/docker-compose.yml`
2. Turn **Install Jupyter on the host** off (not needed) — or leave it on as a fallback terminal.
3. Deploy. First boot ≈ 1 min for packages + tailscale, ≈ 3 more min (background) for the python venv.

## Connect
* **Tailscale SSH** (primary): the box joins the tailnet as `gpu-box`.
  * With a `TS_AUTHKEY` it joins by itself.
  * Without one it prints a one-time login URL: `docker logs gpu-box | grep login.tailscale.com`
    (via `brev shell <instance>` or the Brev/Jupyter terminal). Open it once.
  * Then from the laptop: `gpu-box push` (sends secrets) → `gpu-box ssh`.
* **Brev's own way**: `brev shell <instance>` then `docker exec -it gpu-box bash`.

## Secrets (never committed)
| var | purpose |
|---|---|
| `TS_AUTHKEY` | optional Tailscale auth key (ephemeral, pre-authorized, tag `gpu-box`) |
| `GH_TOKEN` | GitHub token with write access to the data repo |
| `GH_DATA_REPO` | default `Arety30/gpu-box-data` |

Provide them as **Launchable parameters / org secrets** (fully automatic), or drop a
`secrets.env` into `/workspace` (the laptop helper does this over Tailscale SSH).

## Use
```
train                      # LoRA on /workspace/data/in/train.jsonl → /workspace/data/out/<run>/
train unsloth/Llama-3.1-8B-Instruct
gpu-box-sync once          # push now (also runs every 2 min and on container stop)
nvidia-smi
```
