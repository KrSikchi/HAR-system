# Issue fixes — step 1 never completes / step 2 fires with the lid still on

Scope: PTS-01 step 1 (`PRESENT_TRAY`) and the false early trigger of step 2
(`OPEN_TRAY`) while the props are still in the step-1 layout. Nothing about
HOI, step order or step 7 changes.

## Physical step-1 arrangement (ground truth)

Top-down camera, white sheet, black tray centred on the sheet, yellow lid ON
the tray with the black rim visible around it, pads empty, **nobody in frame**.

## Root causes

### A. Person gate blocked all object detection

`har/perception/perception.py`:

```python
detections = self.detector.detect(frame) if person_present else []
```

`person_gate` defaulted to `True`, so whenever the pose model saw no person
the colour detector was skipped and the trackers received an empty list.
Step 1 is a prop-only dwell (`object_stable(tray)`, 15 frames) that is
supposed to complete with nobody at the rack — it therefore could never
complete.

**Fix:** `PerceptionStack(..., person_gate=False)` is now the default and
`har/app.py` exposes `--person-gate / --no-person-gate` (default off). Pose
and wrists still run every frame for the later HOI steps; they simply no
longer gate the detector unless explicitly opted in.

### B. `tray` is the black rim, not the yellow lid

Nothing in code was wrong here once (A) is fixed; the `tray` colour entry in
`config/colours.yaml` is a low-saturation, low-Value band that targets the
grey-black rim. With the lid on, only the rim *ring* is tray-coloured, so the
blob is smaller than the whole tray. The knobs to raise if the overlay shows
no `tray` box under desk lighting are now documented in `colours.yaml`:

* `colours.tray` V upper bound `110 -> 130` (or 150 for a washed-out rim),
* `colours.tray` S upper bound `60 -> 80` if the rim picks up a colour cast,
* `detector.min_area` `300 -> 200` if the visible ring is thin.

### C. `tray_slot` was misaligned with a mid-frame tray

`protocols/pts01.yaml` had `tray_slot: [0.34, 0.48, 0.66, 0.88]`. On the
real step-1 framing the tray (and hence the lid centre) sits around
y ≈ 0.45–0.50. `y1 = 0.48` put the resting lid centre *outside* the slot, so
`object_left_zone(tray_lid, tray_slot)` was true from frame one and the
validator's later-step scan emitted `OUT_OF_ORDER OPEN_TRAY` while
`PRESENT_TRAY` was still pending.

**Fix:** `tray_slot: [0.30, 0.32, 0.70, 0.68]`. Invariant (now stated in the
YAML): with the lid ON the tray, the lid centre must lie inside `tray_slot`;
step 2 is only for the lid slid horizontally clear of that box. `zone_red`
(x ≥ 0.70) and `zone_blue` (x ≤ 0.30) are untouched and still do not overlap
the slot (they touch at the edges).

## Tests added

* `tests/test_perception_stack.py` — gate off by default: detector runs and
  props are measured with `person_present=False` and no wrists; opt-in gate
  still skips the detector.
* `tests/test_predicates.py` — `object_left_zone` false with lid centre inside
  `tray_slot`, true when slid out; `object_stable(tray)` with no hands.
* `tests/test_validator.py::ValidatorStep1LayoutTests` — against the real
  `pts01.yaml`: lid centre at (0.50, 0.48) is inside `tray_slot`; 90 frames of
  step-1 layout with nobody in frame complete `PRESENT_TRAY` with zero
  violations and no OUT_OF_ORDER/SKIPPED; sliding the lid right afterwards
  completes `OPEN_TRAY`.

## How to verify on camera

```bash
python -m har.app --source 0 --detector color            # person gate is off by default
```

1. Step-1 layout, nobody in frame. Overlay must show a `tray` box on the black
   rim (not the lid) and a `tray_lid` box on the yellow lid, with the lid's
   centre dot inside the `tray_slot` rectangle. If no `tray` box appears,
   raise the `colours.yaml` knobs listed under (B) — config only.
2. Leave the props still for ~1 s: step 1 `COMPLETED`, cursor on step 2, no
   alert, no voice `voice_alert`. No person needs to enter the frame.
3. Slide the lid horizontally until its centre leaves `tray_slot`, pause ~1 s
   in frame: step 2 `COMPLETED`.
4. If the tray is framed noticeably higher/lower than mid-frame, move
   `tray_slot` in `protocols/pts01.yaml` until the resting lid centre is inside
   it and the slid-off lid centre is outside; do not touch Python.

`--person-gate` remains available as a frame-rate optimisation for setups
where a person is guaranteed in frame whenever anything protocol-relevant
happens — it is not appropriate for the demo's step 1.
