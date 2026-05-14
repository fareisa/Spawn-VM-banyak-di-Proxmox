#!/bin/bash
set -euo pipefail

# --- Defaults ---
INPUT=""
OUTPUT_DIR="."
FORCE=false
TEMPLATE="./main-tf.tpl"

# --- Help ---
show_help() {
  cat <<EOF
Usage:
  $(basename "$0") [OPTIONS]

Options:
  -i, --input FILE
  -o, --output DIR
  -t, --template FILE (default: main.tf.tpl)
  -f, --force
  -h, --help
EOF
}

[[ $# -eq 0 ]] && { show_help; exit 0; }

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input) INPUT="$2"; shift 2 ;;
    -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
    -t|--template) TEMPLATE="$2"; shift 2 ;;
    -f|--force) FORCE=true; shift ;;
    -h|--help) show_help; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# --- Basic validation ---
[[ -z "$INPUT" || -z "$OUTPUT_DIR" ]] && { echo "Error: missing input/output"; exit 1; }
[[ ! -f "$INPUT" ]] && { echo "Error: input file not found"; exit 1; }
[[ ! -f "$TEMPLATE" ]] && { echo "Error: template not found"; exit 1; }

echo "Validating YAML..."

# --- Top-level ---
for f in project_name proxmox.endpoint proxmox.api_token proxmox.node proxmox.template_id vms; do
  yq -e ".$f" "$INPUT" >/dev/null || { echo "Error: missing $f"; exit 1; }
done

VM_COUNT=$(yq -r '.vms | length' "$INPUT")

# --- VM validation ---
for ((i=0;i<VM_COUNT;i++)); do
  VM_NAME=$(yq -r ".vms[$i].name // \"unknown\"" "$INPUT")
  for f in name cores memory user ssh_keys disks network password; do
    yq -e ".vms[$i].$f" "$INPUT" >/dev/null || {
      echo "Error: vms[$i] ($VM_NAME) missing $f"; exit 1;
    }
  done

  # --- Disk validation ---
  DISK_COUNT=$(yq -r ".vms[$i].disks // [] | length" "$INPUT")
  if (( DISK_COUNT > 0 )); then
    for ((d=0;d<DISK_COUNT;d++)); do
      for f in datastore interface size; do
        yq -e ".vms[$i].disks[$d].$f" "$INPUT" >/dev/null || {
          echo "Error in vms[$i] ($VM_NAME): vms[$i].disks[$d] missing $f"; exit 1;
        }
      done
    done

    DUP_DISK=$(yq -r ".vms[$i].disks[].interface" "$INPUT" | sort | uniq -d || true)
    [[ -n "$DUP_DISK" ]] && { echo "Error: duplicate disk interface in vms[$i] ($VM_NAME): $DUP_DISK"; exit 1; }
  fi

  # --- Network validation ---
  NET_COUNT=$(yq -r ".vms[$i].network // [] | length" "$INPUT")

  if (( NET_COUNT > 0 )); then
    GW_COUNT=0
    GW_INDEX=-1
    DHCP_COUNT=0

    for ((n=0;n<NET_COUNT;n++)); do
      BRIDGE=$(yq -r ".vms[$i].network[$n].bridge // \"\"" "$INPUT")
      if [[ -z "$BRIDGE" ]]; then
        echo "Error in vms[$i] ($VM_NAME): vms[$i].network[$n] missing bridge"
        exit 1
      fi

      IP=$(yq -r ".vms[$i].network[$n].ip // \"\"" "$INPUT")
      GW=$(yq -r ".vms[$i].network[$n].gateway // \"\"" "$INPUT")

      # Safe increment (no &&)
      if [[ "$IP" == "dhcp" ]]; then
        DHCP_COUNT=$((DHCP_COUNT+1))
      fi

      if [[ -n "$GW" ]]; then
        GW_COUNT=$((GW_COUNT+1))
        GW_INDEX=$n
      fi
    done


    # --- IP validations ---
    if (( GW_COUNT > 1 )); then
      echo "Error: multiple gateways in vms[$i] ($VM_NAME)"
      exit 1
    fi

    if (( GW_COUNT == 1 && GW_INDEX != 0 )); then
      echo "Error in vms[$i] ($VM_NAME): gateway defined on network[$GW_INDEX], must be on network[0] / First defined interface"
      exit 1
    fi

    # if (( GW_COUNT == 1 && GW_INDEX != 0 )); then
    #   echo "Error: gateway must be on network[0]"
    #   exit 1
    # fi

    # FIRST_IP=$(yq -r ".vms[$i].network[0].ip // \"\"" "$INPUT")

    # if [[ "$FIRST_IP" == "dhcp" ]]; then
    #   if (( GW_COUNT > 0 )); then
    #     echo "Error: cannot define gateway when network[0] uses DHCP"
    #     exit 1
    #   fi
    # fi


    if (( DHCP_COUNT >= 1 && GW_COUNT >= 1 )); then
      echo "Error in vms[$i] ($VM_NAME): cannot mix DHCP and gateway in network configuration"
      exit 1
    fi


    if (( GW_COUNT > 1 )); then
      echo "Error: multiple gateways in vms[$i] ($VM_NAME)"
      exit 1
    fi

#    if (( DHCP_COUNT == NET_COUNT )); then
#      echo "Error in vms[$i] ($VM_NAME): full DHCP not allowed"
#      exit 1
#    fi

    if (( DHCP_COUNT == NET_COUNT && DHCP_COUNT > 1 )); then
      echo "Error in vms[$i] ($VM_NAME): full DHCP not allowed"
      exit 1
    fi  
  
  fi
done

# --- Duplicate VM names ---
DUP=$(yq -r '.vms[].name' "$INPUT" | sort | uniq -d || true)
[[ -n "$DUP" ]] && { echo "Error: duplicate VM names: $DUP"; exit 1; }

echo "Validation OK"

# --- Output ---
PROJECT=$(yq -r '.project_name' "$INPUT")
OUT_PATH="$OUTPUT_DIR/$PROJECT"

if [[ -d "$OUT_PATH" ]]; then
  if [[ "$FORCE" == true ]]; then
    rm -rf "$OUT_PATH"
  else
    read -p "Replace $OUT_PATH? [y/N]: " c
    [[ ! "$c" =~ ^[yY]$ ]] && exit 0
    rm -rf "$OUT_PATH"
  fi
fi

mkdir -p "$OUT_PATH"

# --- Export ---
export endpoint=$(yq -r '.proxmox.endpoint' "$INPUT")
export api_token=$(yq -r '.proxmox.api_token' "$INPUT")
export node=$(yq -r '.proxmox.node' "$INPUT")
export template_id=$(yq -r '.proxmox.template_id' "$INPUT")
export vms_json=$(yq -o=json '.vms' "$INPUT")

# --- Render ---
echo "Rendering Terraform..."
envsubst '$endpoint $api_token $node $template_id $vms_json' < "$TEMPLATE" > "$OUT_PATH/main.tf"

echo "Done → $OUT_PATH/main.tf"
