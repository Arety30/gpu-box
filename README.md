# gpu-box 🚀
### A disposable GPU development machine you can reach from your own devices.

Spin up a GPU-backed Linux workspace for experiments without having to configure every machine by hand. This project packages a container-based environment for NVIDIA Brev, CUDA-enabled workloads, and private remote access over Tailscale.

## ✨ What's inside

- Ubuntu-based container with NVIDIA GPU access
- CUDA/cuDNN environment for GPU workloads
- Tailscale SSH for private remote terminal access
- Workspace data sync to a separate **private** repository
- Helpers for common model fine-tuning workflows

## 🧰 Deploy

Follow the steps in the repository's `docker-compose.yml` and the NVIDIA Brev setup flow:

1. Open the repo's `docker-compose.yml` in Brev's Docker Compose configuration.
2. Configure secret environment variables using the platform's secret manager.
3. Deploy, then follow the container logs for first-run setup.

Do **not** commit authentication keys or personal credentials. The scripts expect secrets to be supplied at runtime.

## 💻 Example commands

Once deployed and connected to the container, the environment provides shortcuts such as:

```bash
nvidia-smi
train
gpu-box-sync once
```

Available commands depend on the deployed image and configuration.

## 🔐 Security notes

Keep tokens and credentials in a secret manager or an untracked local environment file. Never put live keys in code, logs, screenshots, or a public repository. Workspace data is configured to sync to a separate private repository; review that destination before using real or sensitive data.

## ⚠️ Project status

This is a personal infrastructure experiment. Cloud provider availability, GPU access, pricing, and runtime behavior depend on the provider and deployment settings.

---
Built by Arety for hands-on ML and infrastructure experiments.