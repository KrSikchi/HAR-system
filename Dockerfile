# syntax=docker/dockerfile:1
#
# Docker image for SIH26174 — AI Human Activity Recognition (HAR) for on-board
# BAS experiments.
#
# The default image is a CPU-only deployment:
#   * no NVIDIA GPU / CUDA runtime required;
#   * opencv is compiled against FFmpeg, which is installed below;
#   * espeak-ng + libespeak are installed for the optional offline voice path.
#
# To build a CUDA image, set PYTORCH_INDEX_URL to a CUDA index, e.g.
#   docker build --build-arg PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu124 -t har-system:cu124 .
# (A GPU compose deployment also needs `deploy.resources.reservations.devices`
#  or a `--gpus` override.)

FROM python:3.11-slim-bookworm

ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cpu

# Keep Python from writing bytecode / buffering output in a container.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

# System packages needed by OpenCV (video/GUI) and pyttsx3 (offline TTS).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        passwd \
        ffmpeg \
        libgl1 \
        libglib2.0-0 \
        libsm6 \
        libxext6 \
        libxrender1 \
        libgomp1 \
        espeak-ng \
        libespeak-ng1 \
        libespeak-ng-libespeak1 \
        espeak-ng-data \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 1. Install CPU-only torch/torchvision first so ultralytics never pulls the
#    ~2.5 GB CUDA-family wheels from PyPI.  Versions match requirements.lock
#    (the demo-machine dependency set).
RUN pip install --no-cache-dir \
        --index-url "${PYTORCH_INDEX_URL}" \
        --extra-index-url https://pypi.org/simple \
        "torch==2.14.0" \
        "torchvision==0.29.0"

# 2. Install the rest of the application's runtime dependencies.  torch is
#    already satisfied, so this resolves ultralytics/opencv/numpy/etc. only.
COPY requirements.txt ./
RUN pip install --no-cache-dir \
        --extra-index-url "${PYTORCH_INDEX_URL}" \
        -r requirements.txt

# 3. Copy the application.  Everything needed for the default demo (models/,
#    protocols/, config/, demo/, tests/fixtures) is part of the image.
COPY . .

# Non-root runtime user.  The default out-dir (/work/runs) is owned by this
# user, so `docker run` works with or without a volume mount.
RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin har \
    && mkdir -p /work/runs /app/runs \
    && chown -R har:har /work /app/runs \
    && chmod +x /app/docker/entrypoint.sh

USER har

# GUI / MJPEG endpoint.  The app always binds 0.0.0.0.
EXPOSE 8080

# The browser GUI and the MJPEG stream are served on the same HTTP port.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import os, sys, urllib.request; port = os.environ.get('HAR_STREAM_PORT', '8080'); sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:%s/status' % port, timeout=3).status == 200 else 1)" || exit 1

ENTRYPOINT ["/app/docker/entrypoint.sh"]
