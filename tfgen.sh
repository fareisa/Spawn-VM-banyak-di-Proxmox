#!/bin/bash
set -eo pipefail

INPUT="vm.yaml"
OUTPUT_DIR="."
TEMPLATE="main.tf.tpl"

PROJECT=$(yq -r '.project_name' "$INPUT")
OUT_PATH="$OUTPUT_DIR/$PROJECT"

mkdir -p "$OUT_PATH"

export endpoint=$(yq -r '.proxmox.endpoint' "$INPUT")
export api_token=$(yq -r '.proxmox.api_token' "$INPUT")
export node=$(yq -r '.proxmox.node' "$INPUT")
export template_id=$(yq -r '.proxmox.template_id' "$INPUT")

export vms_json=$(yq -o=json '.vms' "$INPUT")

echo "Rendering Terraform..."
envsubst < "$TEMPLATE" > "$OUT_PATH/main.tf"

echo "Done: $OUT_PATH"