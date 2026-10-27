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
            echo "ERROR: MOOSHIEUI_ADMIN_PASS is a placeholder. Set a real password." >&2
            exit 1
            ;;
    esac
fi

# ── Volume ownership / writability ──
# The image runs as uid 10001. A volume created by root (e.g. a RunPod volume)
# must be handed to that user once: chown -R 10001:10001 <volume>.
for dir in "${DATA_DIR}" "${DATA_DIR}/models"; do
    if [ -e "$dir" ] && [ ! -w "$dir" ]; then
        echo "ERROR: $dir is not writable by uid $(id -u) (gid $(id -g))." >&2
        echo "Fix ownership once (as root): chown -R 10001:10001 ${DATA_DIR}" >&2
        exit 1
    fi
done

mkdir -p "${DATA_DIR}/models" "${DATA_DIR}/gallery" "${DATA_DIR}/thumbnails" "${DATA_DIR}/comfyui/output"

# ── config.json (the "python not found" fix) ──
# The server runs ComfyUI with <venv_path>/bin/python, taking venv_path from
# ${DATA_DIR}/config.json. The image bakes that file at build time, but a volume
# mounted on ${DATA_DIR} (RunPod) hides it; the server then starts from a blank
# config and fails with "Python not found at '/bin/python'".
# Fill in only the install fields when they are missing or empty, and keep every
# other setting the server has saved. Uses the system python3, not the venv.
python3 - "${DATA_DIR}/config.json" "${COMFYUI_PATH}" <<'PY'
import json, os, sys

path, comfyui = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        config = json.load(f)
    if not isinstance(config, dict):
        raise ValueError("not a JSON object")
except FileNotFoundError:
    config = {}
except (ValueError, OSError) as e:
    print(f"WARNING: {path} unreadable ({e}); recreating it", file=sys.stderr)
    config = {}

required = {"comfyui_path": comfyui, "venv_path": f"{comfyui}/.venv", "setup_complete": True}
defaults = {
    "auto_start": True,
    "browser_mode": True,
    "ui_server_port": 3200,
    "lan_enabled": True,
    "server_mode": "autolaunch",
}

changed = []
for key, value in required.items():
    if not config.get(key):
        config[key] = value
        changed.append(key)
for key, value in defaults.items():
    if key not in config:
        config[key] = value
        changed.append(key)

if changed:
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(config, f, indent=2)
    os.replace(tmp, path)
    print(f"config.json: set {', '.join(changed)}")
PY

# Fail early with a clear message rather than inside the server.
if [ ! -x "${COMFYUI_PATH}/.venv/bin/python" ]; then
    echo "ERROR: ComfyUI venv python missing at ${COMFYUI_PATH}/.venv/bin/python (image build problem)." >&2
    exit 1
fi

# ── Link ComfyUI mutable dirs to persistent storage ──
link_dir () {
    src="$1"; target="$2"
    if [ -L "$src" ] && [ "$(readlink "$src")" = "$target" ]; then
        return
    fi
    rm -rf "$src"
    ln -s "$target" "$src"
}

link_dir "${COMFYUI_PATH}/models" "${DATA_DIR}/models"
link_dir "${COMFYUI_PATH}/output" "${DATA_DIR}/comfyui/output"
# custom_nodes is deliberately NOT linked: the image installs the pinned packs
# and MooshieUI's own nodes there, and an empty volume dir would hide them.

for subdir in checkpoints clip clip_vision configs controlnet diffusers diffusion_models embeddings gligen hypernetworks loras photomaker style_models unet upscale_models vae vae_approx ultralytics; do
    mkdir -p "${DATA_DIR}/models/${subdir}"
done

exec "$@"
