#!/usr/bin/env bash
# Container entrypoint for the HAR system.
#
# `har.app` is a normal CLI entrypoint, so this script turns it into a
# long-lived deployment service:
#   * defaults to the shipped demo source, looping forever;
#   * always binds the browser GUI / MJPEG stream on 0.0.0.0;
#   * writes run artefacts to a writable volume (/work/runs by default);
#   * lets every CLI flag be configured through environment variables.
#
# Most settings have a sensible default.  Override them with .env (see the
# .env.example file) or with `docker compose run -e HAR_SOURCE=... har ...`.
set -euo pipefail

# --- defaults ---------------------------------------------------------------
: "${HAR_SOURCE:=demo/correct.mp4}"       # see har/app.py for supported values
: "${HAR_PROTOCOL:=protocols/pts01.yaml}"
: "${HAR_COLOURS:=config/colours.yaml}"
: "${HAR_OUT_DIR:=/work/runs/latest}"
: "${HAR_DETECTOR:=color}"                # color | yolo
: "${HAR_WRISTS:=auto}"                   # auto | pose | hsv | none
: "${HAR_MAX_FRAMES:=0}"                  # 0 = no limit
: "${HAR_LOOP:=1}"                        # 1 = keep processing after EOF
: "${HAR_RECORD:=0}"                      # 1 = write MP4 recordings
: "${HAR_HEADLESS:=0}"                    # 1 = explicit headless mode
: "${HAR_VOICE:=0}"                       # 1 = enable offline TTS
: "${HAR_STREAM_HOST:=0.0.0.0}"
: "${HAR_STREAM_PORT:=8080}"

# --- build args -------------------------------------------------------------
args=(
  --source "${HAR_SOURCE}"
  --protocol "${HAR_PROTOCOL}"
  --colours "${HAR_COLOURS}"
  --out-dir "${HAR_OUT_DIR}"
  --detector "${HAR_DETECTOR}"
  --wrists "${HAR_WRISTS}"
  --stream-host "${HAR_STREAM_HOST}"
  --stream-port "${HAR_STREAM_PORT}"
)

if [ "${HAR_MAX_FRAMES}" != "0" ]; then
  args+=(--max-frames "${HAR_MAX_FRAMES}")
fi
if [ "${HAR_LOOP}" = "1" ]; then
  args+=(--loop)
fi
if [ "${HAR_RECORD}" = "1" ]; then
  args+=(--record)
fi
if [ "${HAR_HEADLESS}" = "1" ]; then
  args+=(--headless)
fi
# Voice requires a local TTS driver.  espeak-ng is installed in the image, but
# most headless servers have no audio device, so default to --no-voice and let
# the on-screen banner carry alerts.
if [ "${HAR_VOICE}" != "1" ]; then
  args+=(--no-voice)
fi

# --- extra flags ------------------------------------------------------------
# Shell-split on whitespace so users can pass any remaining CLI flag, e.g.
# HAR_EXTRA_ARGS="--imgsz 640 --conf 0.5".  Values containing spaces and
# quotes are not supported here; use a custom command in that case.
if [ -n "${HAR_EXTRA_ARGS:-}" ]; then
  read -r -a extra_args <<< "${HAR_EXTRA_ARGS}"
  args+=("${extra_args[@]}")
fi

echo "HAR container starting: python -m har.app ${args[*]}"
exec python -m har.app "${args[@]}"
