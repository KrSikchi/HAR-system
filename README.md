# SIH26174 — AI Human Activity Recognition for On-board BAS Experiments

**Problem statement:** SIH26174, Indian Space Research Organisation (ISRO), Smart India
Hackathon 2026, Software / Smart Automation.

An **offline** system that watches a fixed-payload camera, tracks which step of a
pre-defined experiment the astronaut is on, announces the next step, speaks up when a step
is skipped or performed out of sequence, and leaves a timestamped log plus a stored and
streamed video — with no ground station in the loop.

**Protocol implemented:** `PTS-01 — Payload Tray Sorting & Sample Transfer`, 8 steps.

---

## Quickstart

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python -m unittest discover        # 160 tests; heavy-dep ones skip in a bare interpreter
```

Voice output needs a local TTS driver (offline, no cloud): SAPI5 on Windows,
`espeak-ng` on Linux (`sudo apt install espeak-ng`). Without it the system still
runs — alerts move to the on-screen banner and `--no-voice` silences the warning.

## Deploy with Docker

The repository ships a production-oriented Docker setup (CPU image by
default; optional CUDA build).  It runs the full system as a long-lived
service: it loops the shipped demo footage, serves the browser GUI + MJPEG
stream on `0.0.0.0:8080`, and writes `events.jsonl` / `events.csv` /
`meta.json` (plus recordings when enabled) to a persistent volume.

```bash
# Build and start
cp .env.example .env          # optional, then edit anything you like
docker compose up -d --build

# Open the console
#   http://localhost:8080
# The stream is also available directly at /stream.

# Inspect
docker compose logs -f
docker compose ps

# Run artefacts live on a named volume (har-runs)
docker compose exec har ls -l /work/runs/latest

# Stop
docker compose down           # add -v to also delete the run-volume
```

Everything the CLI accepts can be configured with environment variables
(`.env.example` documents them).  The main ones:

| Variable | Default | Meaning |
|---|---|---|
| `HAR_SOURCE` | `demo/correct.mp4` | `0` for a live camera, otherwise a file inside the image or mounted path |
| `HAR_LOOP` | `1` | keep re-processing after the source ends so the service keeps running |
| `HAR_RECORD` | `0` | record MP4s into the out-dir |
| `HAR_VOICE` | `0` | enable offline TTS (`espeak-ng` is installed, but most headless hosts have no audio device) |
| `HAR_DETECTOR` / `HAR_WRISTS` | `color` / `auto` | same as the CLI flags |
| `HAR_EXTRA_ARGS` | (empty) | shell-splits extra CLI flags, e.g. `--imgsz 640 --conf 0.5` |
| `HAR_HOST_PORT` | `8080` | host port mapping for the console |
| `HAR_STREAM_PORT` | `8080` | container port the GUI/stream (and health check) listen on |

Notes:

* The image runs as a non-root user (`har`, UID 10001).  A bind-mount for the
  run directory must be writable by that UID; the default `har-runs` named
  volume is already set up for it.
* To use a live camera, uncomment the `devices` block in
  `docker-compose.yml` and set `HAR_SOURCE=0`.
* Default build installs CPU-only PyTorch.  For a GPU image, build with a
  CUDA PyTorch index, e.g.
  `docker build --build-arg PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu124 -t har-system:cu124 .`
  and enable GPU access in your compose override.
* Docker builds resolve dependencies online; the committed `wheelhouse/`
  remains the offline-without-Docker path described below.

## Run it (no camera needed)

```bash
# Gate G1: the whole system on synthetic footage, headless, exit 0
.venv/bin/python tools/make_synthetic_video.py                 # render + self-verify
.venv/bin/python -m har.app --source tests/fixtures/synthetic_correct.mp4 \
    --headless --out-dir runs/g1
cat runs/g1/events.jsonl       # 8 COMPLETED in order + PROTOCOL_COMPLETE

# The wrong-order run: spoken "Out of sequence" + a VIOLATION row
.venv/bin/python -m har.app --source tests/fixtures/synthetic_wrong_order.mp4 \
    --headless --out-dir runs/g1_wrong
cat runs/g1_wrong/events.csv

# Zero-dependency replay of the canned event fixtures (log/voice stub)
.venv/bin/python tools/replay_events.py --fixture wrong_order
.venv/bin/python -m har.app --headless --stub --no-voice
```

## Run it (GUI, stream, recording)

```bash
# Live camera, browser GUI + MJPEG stream + local recording (gate G2 shape)
.venv/bin/python -m har.app --source 0 --detector color --record \
    --stream-host 0.0.0.0 --stream-port 8080
# then open http://<host>:8080/ on any machine on the LAN

# Same, replayed from a file (the webcam-fail fallback), looping for demos
.venv/bin/python -m har.app --source demo/correct.mp4 --loop --record \
    --stream-host 0.0.0.0 --stream-port 8080
```

Useful flags: `--headless` · `--no-voice` · `--max-frames N` · `--loop` ·
`--detector color|yolo` · `--wrists auto|pose|hsv|none` (`auto`: pose for a live
camera, `hsv` for the shipped *rendered* footage; pass `--wrists pose` for real
recordings) · `--pose-every-n N` · `--imgsz N` · `--conf F` · `--contract`.

Every run writes `--out-dir` (default `runs/latest`): `events.jsonl` +
`events.csv` (one row per step event, flushed per event), `meta.json` (run
metadata), and with `--record`, `recordings/run_<ts>.mp4`.

## What a judge sees (deliverables)

| # | Deliverable | Where |
|---|---|---|
| D1 | Continuous local video processing | live FPS readout in the GUI banner and HUD |
| D2 | Next-step suggestion | GUI "NEXT INSTRUCTION" card + top-line of the HUD |
| D3 | Voice alert on skip / out-of-sequence | `OfflineSpeaker` (pyttsx3, fully offline); wrong-order demo above |
| D4 | Timestamped structured log | `runs/*/events.jsonl` + mirrored `events.csv`, fsync per event |
| D5 | Stream to a specific IP **and** store locally | `http://<host>:8080/stream` + `recordings/*.mp4` |
| D6 | GUI for monitoring | one page: video, 8-step checklist, red violation banner, log tail, FPS |
| D7 | Trained AI model, offline | **partially, openly:** pretrained YOLO11n-pose (real trained net, offline) for wrists/person gating; protocol objects by classical HSV colour — see `docs/DEVELOPMENT_PLAN.md` §2 |

## Layout

```
har/
├── contracts.py       frozen cross-person data contracts (stdlib only)
├── app.py             CLI entrypoint / composition root       [Person C]
├── perception/        colour detection, pose, tracking        [Person B]
├── protocol/          protocol model, sequence validator      [Person A]
├── out/               event log, speaker, recorder, streamer  [Person C]
└── ui/                browser GUI, MJPEG stream, HUD overlay  [Person C]
protocols/             PTS-01 procedure definition
config/                tracker tuning + HSV colour ranges
models/                pretrained YOLO weights (read-only)
tests/                 unit tests + JSON/mp4 fixtures
tools/                 replay_events, make_synthetic_video, probe_fps, evaluate
requirements.lock      frozen dependency set (C11)
wheelhouse/            offline install media (see its README)
```

The three people own disjoint file sets, so they work in parallel without merge conflicts.
`har/contracts.py` and `protocols/pts01.yaml` are the only shared files.

**No model training is in scope.** Protocol objects are detected by HSV colour, not by a
network we train — see `docs/DEVELOPMENT_PLAN.md` §2 for the reasoning and for how we state
the gap honestly.

## Offline proof

```bash
bash wheelhouse/download.sh     # once, on a networked machine (fills wheelhouse/)
# unplug the network, then:
python3 -m venv .venv
.venv/bin/pip install --no-index --find-links wheelhouse/ -r requirements.lock
.venv/bin/python -m har.app --source demo/correct.mp4 --headless --no-voice
```

The committed wheelhouse subset already covers the GUI and voice layers
(`pip install --no-index --find-links wheelhouse/ pyttsx3 flask` verified with
no index); `download.sh` completes the set with numpy/opencv/torch/ultralytics
before travel. After that the demo runs in airplane mode end to end.

## Status (verified 2026-09-02, this branch)

`.venv/bin/python -m unittest discover` → **160 tests, OK** (84 run in a bare
interpreter, 76 skip without cv2/flask/pyttsx3/PyYAML).

| Layer | State |
|---|---|
| Contracts, protocol loader, predicates, `SequenceValidator`, `UiStatus` | landed + tested (Person A) |
| Colour detector, trackers, interaction FSM, pose, `PerceptionStack`, rack frame | landed + tested (Person B) |
| Event log, voice, recorder, streamer, GUI, HUD, CLI | **landed + tested (Person C)** |
| Gate G1 (headless spine on synthetic footage) | **PASS** — 8/8 COMPLETED + PROTOCOL_COMPLETE; wrong-order run: one OUT_OF_ORDER, no completion |
| Demo dataset + evaluation metrics | `demo/`, `tools/evaluate.py`, `docs/METRICS.md`, `docs/PERF.md` |

One deliberate deviation to know about: on *dense* video the wrong-order run
yields exactly one OUT_OF_ORDER (and never completes), matching
`demo/ground_truth.json` and `tools/crosscheck_g1.py`; the OUT_OF_ORDER+SKIPPED
pair lives at the sparse-fixture layer (`tests/fixtures/events_wrong_order.jsonl`,
covered by the validator tests). `tools/make_synthetic_video.py` documents the
semantics precisely.
