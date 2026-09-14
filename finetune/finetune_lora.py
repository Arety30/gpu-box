#!/usr/bin/env python3
"""LoRA fine-tune on a GPU box (L4 24 GB is plenty for 1B–8B), export GGUF for Ollama.
Env: BASE (HF model), DATA (chat-format jsonl: {"messages":[{role,content},...]}),
     OUT (dir), EPOCHS, LR, MAX_SEQ, QUANT (gguf quant, default q4_k_m), LOAD_4BIT (0/1).
"""
import os, torch
from datasets import load_dataset
from transformers import TrainingArguments
from trl import SFTTrainer
from unsloth import FastLanguageModel
from unsloth.chat_templates import get_chat_template

BASE = os.environ.get("BASE", "unsloth/Llama-3.2-1B-Instruct")
DATA = os.environ.get("DATA", "/workspace/data/in/train.jsonl")
OUT = os.environ.get("OUT", "/workspace/data/out/run")
MAX_SEQ = int(os.environ.get("MAX_SEQ", "1024"))
EPOCHS = float(os.environ.get("EPOCHS", "3"))
LR = float(os.environ.get("LR", "2e-4"))
QUANT = os.environ.get("QUANT", "q4_k_m")
LOAD_4BIT = os.environ.get("LOAD_4BIT", "0") == "1"   # 24 GB VRAM: bf16 is fine up to ~8B
TEMPLATE = os.environ.get("CHAT_TEMPLATE", "llama-3.1")

model, tokenizer = FastLanguageModel.from_pretrained(
    model_name=BASE, max_seq_length=MAX_SEQ, load_in_4bit=LOAD_4BIT,
    dtype=torch.bfloat16 if torch.cuda.is_bf16_supported() else None)
model = FastLanguageModel.get_peft_model(
    model, r=16, lora_alpha=16, lora_dropout=0.0, bias="none",
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
    use_gradient_checkpointing="unsloth", random_state=42)
tokenizer = get_chat_template(tokenizer, chat_template=TEMPLATE)

ds = load_dataset("json", data_files=DATA, split="train")
ds = ds.map(lambda ex: {"text": tokenizer.apply_chat_template(
    ex["messages"], tokenize=False, add_generation_prompt=False)})

trainer = SFTTrainer(
    model=model, tokenizer=tokenizer, train_dataset=ds, dataset_text_field="text",
    max_seq_length=MAX_SEQ, packing=False,
    args=TrainingArguments(
        per_device_train_batch_size=4, gradient_accumulation_steps=2, warmup_steps=5,
        num_train_epochs=EPOCHS, learning_rate=LR,
        fp16=not torch.cuda.is_bf16_supported(), bf16=torch.cuda.is_bf16_supported(),
        logging_steps=1, optim="adamw_8bit", weight_decay=0.01,
        lr_scheduler_type="linear", seed=42, output_dir=os.path.join(OUT, "checkpoints"),
        save_strategy="no", report_to="none"))
trainer.train()

model.save_pretrained(os.path.join(OUT, "lora"))
tokenizer.save_pretrained(os.path.join(OUT, "lora"))
model.save_pretrained_gguf(os.path.join(OUT, "gguf"), tokenizer, quantization_method=QUANT)
with open(os.path.join(OUT, "Modelfile"), "w") as f:
    f.write(f"FROM ./gguf/unsloth.{QUANT.upper()}.gguf\nPARAMETER temperature 0.6\n")
print(f"\n✅ done → {OUT}  (gguf/, lora/, Modelfile) — synced to GitHub release 'outputs'")
