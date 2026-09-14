#!/usr/bin/env bash
# One-shot twin fine-tune on the box.  Usage:  train [BASE_MODEL]
#   inputs : /workspace/data/in/train.jsonl        (synced from the data repo)
#   outputs: /workspace/data/out/<run>/             (adapter + GGUF, synced back)
set -euo pipefail
. /workspace/venv/bin/activate 2>/dev/null || { echo "venv not ready yet — tail /workspace/pip.log"; exit 1; }
[ -f /workspace/venv/.ready ] || { echo "venv still installing — tail /workspace/pip.log"; exit 1; }
export BASE="${1:-${BASE:-unsloth/Llama-3.2-1B-Instruct}}"
export DATA="${DATA:-/workspace/data/in/train.jsonl}"
export OUT="${OUT:-/workspace/data/out/$(date +%Y%m%d-%H%M)-$(basename "$BASE")}"
export HF_HUB_ENABLE_HF_TRANSFER=1
mkdir -p "$OUT"
echo "base=$BASE data=$DATA out=$OUT"
python /workspace/finetune/finetune_lora.py 2>&1 | tee "$OUT/train.log"
gpu-box-sync once || true
