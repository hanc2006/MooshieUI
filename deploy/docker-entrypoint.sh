#!/bin/sh
set -e

DATA_DIR="${MOOSHIEUI_DATA_DIR:-/data}"
COMFYUI_PATH="${COMFYUI_PATH:-/opt/comfyui}"

# ── Admin password guard ──
if [ -n "$MOOSHIEUI_ADMIN_USER" ] || [ -n "$MOOSHIEUI_ADMIN_PASS" ]; then
    if [ -z "$MOOSHIEUI_ADMIN_USER" ] || [ -z "$MOOSHIEUI_ADMIN_PASS" ]; then
        echo "ERROR: Both MOOSHIEUI_ADMIN_USER and MOOSHIEUI_ADMIN_PASS must be set." >&2
        exit 1
    fi
    if [ ${#MOOSHIEUI_ADMIN_PASS} -lt 4 ]; then
        echo "ERROR: MOOSHIEUI_ADMIN_PASS is too short (minimum 4 characters)." >&2
        exit 1
    fi
    case "$(printf '%s' "$MOOSHIEUI_ADMIN_PASS" | tr '[:upper:]' '[:lower:]')" in
        changeme|replace_me)
            echo "" >&2
            echo "========================================================" >&2
            echo "  ERROR: MOOSHIEUI_ADMIN_PASS is a placeholder." >&2
            echo "  The server will not create an admin account with it." >&2
            echo "  Set a strong password before exposing this server." >&2
            echo "========================================================" >&2
            echo "" >&2
            exit 1
            ;;
    esac
fi

# ── Volume ownership / writability ──
for dir in "${DATA_DIR}" "${DATA_DIR}/models"; do
    if [ -e "$dir" ] && [ ! -w "$dir" ]; then
        echo "ERROR: $dir is not writable by uid $(id -u) (gid $(id -g))." >&2
        echo "Fix ownership once (as root): chown -R 10001:10001 ${DATA_DIR}" >&2
        exit 1
    fi
done

# Ensure persistent dirs exist
mkdir -p "${DATA_DIR}/models" "${DATA_DIR}/comfyui/custom_nodes" "${DATA_DIR}/comfyui/output"

# Link ComfyUI mutable dirs to persistent storage
link_dir () {
    src="$1"        # e.g. /opt/comfyui/models
    target="$2"     # e.g. /data/models

    if [ -L "$src" ]; then
        # If symlink points elsewhere, replace it
        if [ "$(readlink "$src")" != "$target" ]; then
            rm -f "$src"
            ln -s "$target" "$src"
        fi
    else
        rm -rf "$src"
        ln -s "$target" "$src"
    fi
}

link_dir "${COMFYUI_PATH}/models" "${DATA_DIR}/models"
link_dir "${COMFYUI_PATH}/custom_nodes" "${DATA_DIR}/comfyui/custom_nodes"
link_dir "${COMFYUI_PATH}/output" "${DATA_DIR}/comfyui/output"

# Create default ComfyUI model subdirectories
for subdir in checkpoints clip clip_vision configs controlnet diffusers diffusion_models embeddings gligen hypernetworks loras photomaker style_models unet upscale_models vae vae_approx ultralytics; do
    mkdir -p "${DATA_DIR}/models/${subdir}"
done

exec "$@"
