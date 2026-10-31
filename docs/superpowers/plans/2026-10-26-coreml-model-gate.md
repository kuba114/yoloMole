# Core ML Model Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export `yolo26s-mole-800px.pt` to Core ML and fail the build unless that model finds the same Mole boxes as the PyTorch model on a local set of close-up skin photos.

**Architecture:** Pure Python functions filter Mole boxes and pair them one-to-one by intersection-over-union. A Mac-only script exports the `.pt` file with Ultralytics and compares both models through Ultralytics `predict`, so both box lists are in original-image pixels. Skin photos stay on the developer machine.

**Tech Stack:** Python 3.12, pytest, ultralytics, Core ML export via Ultralytics (`format="coreml"`). Live Core ML prediction requires macOS.

## Global Constraints

- The reference weights are `yolo26s-mole-800px.pt`.
- Inference size is 800 pixels.
- Keep boxes at confidence 0.30 or higher.
- The stored label is `Mole`.
- A box matches when both labels are `Mole` and the intersection-over-union is at least 0.5.
- An image passes when the mole counts are equal and the boxes pair one-to-one.
- The Core ML file is bundled only after every image in a local set of close-up skin photos passes.
- Those photos stay on the developer machine and are not committed.
- Passing on `testvid.mp4` alone is not enough.
- The phone does not call `yolo-api`.

---

### Task 1: Mole filtering and one-to-one pairing

**Files:**
- Create: `model-check/gate.py`
- Test: `model-check/tests/test_gate.py`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `mole_boxes(rows, names, threshold=0.30) -> list[tuple[float, float, float, float]]`
  - `iou(a, b) -> float` where each box is `(x1, y1, x2, y2)`
  - `pairs_one_to_one(reference, candidate, min_iou=0.5) -> bool`

- [ ] **Step 1: Write the failing test**

Create `model-check/tests/test_gate.py`:

```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from gate import iou, mole_boxes, pairs_one_to_one


NAMES = {0: "images", 1: "Mole"}


def test_mole_boxes_keep_only_moles_at_or_above_threshold():
    rows = [
        (0, 0.90, (0, 0, 10, 10)),
        (1, 0.29, (0, 0, 10, 10)),
        (1, 0.30, (1, 2, 3, 4)),
        (1, 0.80, (5, 6, 7, 8)),
    ]
    assert mole_boxes(rows, NAMES) == [(1, 2, 3, 4), (5, 6, 7, 8)]


def test_iou_of_identical_boxes_is_one():
    box = (0, 0, 10, 10)
    assert iou(box, box) == 1


def test_iou_of_disjoint_boxes_is_zero():
    assert iou((0, 0, 10, 10), (20, 20, 30, 30)) == 0


def test_identical_sets_pair():
    boxes = [(0, 0, 10, 10), (20, 20, 40, 40)]
    assert pairs_one_to_one(boxes, list(reversed(boxes))) is True


def test_different_counts_do_not_pair():
    assert pairs_one_to_one([(0, 0, 10, 10)], []) is False


def test_low_overlap_does_not_pair():
    reference = [(0, 0, 10, 10)]
    candidate = [(6, 6, 16, 16)]
    assert iou(reference[0], candidate[0]) < 0.5
    assert pairs_one_to_one(reference, candidate) is False
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `python3 -m pytest model-check/tests/test_gate.py -v`

Expected: FAIL with `ModuleNotFoundError: No module named 'gate'`

- [ ] **Step 3: Write the minimal implementation**

Create `model-check/gate.py`:

```python
def mole_boxes(rows, names, threshold=0.30):
    kept = []
    for class_id, confidence, xyxy in rows:
        if names[int(class_id)] == "Mole" and float(confidence) >= threshold:
            x1, y1, x2, y2 = xyxy
            kept.append((float(x1), float(y1), float(x2), float(y2)))
    return kept


def iou(a, b):
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    ix1 = max(ax1, bx1)
    iy1 = max(ay1, by1)
    ix2 = min(ax2, bx2)
    iy2 = min(ay2, by2)
    intersection = max(0.0, ix2 - ix1) * max(0.0, iy2 - iy1)
    if intersection == 0:
        return 0.0
    area_a = max(0.0, ax2 - ax1) * max(0.0, ay2 - ay1)
    area_b = max(0.0, bx2 - bx1) * max(0.0, by2 - by1)
    union = area_a + area_b - intersection
    if union <= 0:
        return 0.0
    return intersection / union


def pairs_one_to_one(reference, candidate, min_iou=0.5):
    """Greedy match in reference order. Each candidate is used once. Best IoU below min_iou fails."""
    if len(reference) != len(candidate):
        return False
    unused = set(range(len(candidate)))
    for box in reference:
        best_index = None
        best_score = 0.0
        for index in unused:
            score = iou(box, candidate[index])
            if score > best_score:
                best_score = score
                best_index = index
        if best_index is None or best_score < min_iou:
            return False
        unused.remove(best_index)
    return True
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `python3 -m pytest model-check/tests/test_gate.py -v`

Expected: 6 passed

- [ ] **Step 5: Commit**

```bash
git add model-check/gate.py model-check/tests/test_gate.py
git commit -m "feat: pair Mole boxes for the Core ML gate"
```

---

### Task 2: Export the reference weights to Core ML

**Files:**
- Create: `model-check/export_coreml.py`

**Interfaces:**
- Consumes: `yolo26s-mole-800px.pt` at the repository root
- Produces: `yolo26s-mole-800px.mlpackage` at the repository root. This file is not committed.

- [ ] **Step 1: Write the export script**

Create `model-check/export_coreml.py`:

```python
import sys
from pathlib import Path

from ultralytics import YOLO

ROOT = Path(__file__).resolve().parents[1]
WEIGHTS = ROOT / "yolo26s-mole-800px.pt"
OUTPUT = ROOT / "yolo26s-mole-800px.mlpackage"


def main():
    if not WEIGHTS.is_file():
        print(f"Missing weights: {WEIGHTS}", file=sys.stderr)
        return 2
    YOLO(str(WEIGHTS)).export(format="coreml", imgsz=800, nms=True)
    if not OUTPUT.exists():
        print(f"Export finished without {OUTPUT.name}", file=sys.stderr)
        return 1
    print(OUTPUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Run the export on a Mac**

Run, from the repository root, on macOS with Ultralytics and Core ML tools installed:

```bash
python3 -m pip install ultralytics coremltools
python3 model-check/export_coreml.py
```

Expected: the command prints an absolute path ending in `yolo26s-mole-800px.mlpackage` and exits 0.

On Linux this step is expected to fail inside Ultralytics or coremltools. Do not replace it with an ONNX export. The iPhone app consumes the `.mlpackage`.

- [ ] **Step 3: Commit the script**

```bash
git add model-check/export_coreml.py
git commit -m "feat: export the mole weights to Core ML"
```

---

### Task 3: Compare PyTorch and Core ML on local skin photos

**Files:**
- Create: `model-check/compare_models.py`
- Modify: `.gitignore` (append the two ignore rules below)
- Test: `model-check/tests/test_gate.py` (already passing; this task adds the compare script's empty-directory behavior by running it)

**Interfaces:**
- Consumes: `pairs_one_to_one` and `mole_boxes` from `model-check/gate.py`; `yolo26s-mole-800px.pt`; `yolo26s-mole-800px.mlpackage`
- Produces: exit code 0 only when every image in `model-check/images/` passes. Exit code 2 when the machine, model file, or image directory cannot run the gate. Exit code 1 when an image fails.

- [ ] **Step 1: Ignore local photos and the exported bundle**

Append these lines to `.gitignore`:

```
# Mole journal model gate
model-check/images/
*.mlpackage
```

- [ ] **Step 2: Write the compare script**

Create `model-check/compare_models.py`:

```python
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "model-check"))

from gate import mole_boxes, pairs_one_to_one

WEIGHTS = ROOT / "yolo26s-mole-800px.pt"
COREML = ROOT / "yolo26s-mole-800px.mlpackage"
IMAGES = ROOT / "model-check" / "images"
SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}


def rows_from_result(result):
    rows = []
    for box in result.boxes:
        class_id = int(box.cls[0])
        confidence = float(box.conf[0])
        xyxy = tuple(float(value) for value in box.xyxy[0].tolist())
        rows.append((class_id, confidence, xyxy))
    return rows


def image_passes(pytorch_model, coreml_model, path):
    pytorch = pytorch_model.predict(str(path), imgsz=800, conf=0.30, verbose=False)[0]
    coreml = coreml_model.predict(str(path), imgsz=800, conf=0.30, verbose=False)[0]
    reference = mole_boxes(rows_from_result(pytorch), pytorch.names)
    candidate = mole_boxes(rows_from_result(coreml), coreml.names)
    passed = pairs_one_to_one(reference, candidate)
    print(
        f"{path.name} reference={len(reference)} coreml={len(candidate)} pass={passed}"
    )
    return passed


def main():
    if sys.platform != "darwin":
        print("Core ML prediction requires macOS", file=sys.stderr)
        return 2
    if not WEIGHTS.is_file() or not COREML.exists():
        print("Export the Core ML bundle before comparing", file=sys.stderr)
        return 2
    if not IMAGES.is_dir():
        print(f"Add close-up skin photos to {IMAGES}", file=sys.stderr)
        return 2
    paths = sorted(
        path for path in IMAGES.iterdir() if path.suffix.lower() in SUFFIXES
    )
    if not paths:
        print(f"Add close-up skin photos to {IMAGES}", file=sys.stderr)
        return 2
    from ultralytics import YOLO

    pytorch_model = YOLO(str(WEIGHTS))
    coreml_model = YOLO(str(COREML))
    failed = [path.name for path in paths if not image_passes(pytorch_model, coreml_model, path)]
    if failed:
        print("Failed: " + ", ".join(failed), file=sys.stderr)
        return 1
    print(f"Passed {len(paths)} image(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 3: Run the empty-directory check**

Run from the repository root, with `model-check/images/` absent:

```bash
python3 model-check/compare_models.py
```

Expected on macOS: exit code 2 and `Add close-up skin photos to` on stderr.

Expected on Linux: exit code 2 and `Core ML prediction requires macOS` on stderr. That Linux result is correct. Run the skin-photo gate itself on a Mac.

- [ ] **Step 4: Run the skin-photo gate on a Mac**

Put at least one close-up skin photo in `model-check/images/`. Do not commit those photos. `testvid.mp4` does not satisfy this step.

```bash
python3 model-check/compare_models.py
```

Expected: one `pass=True` line per photo, then `Passed N image(s)`, exit code 0. If any line says `pass=False`, do not copy the `.mlpackage` into the iOS app. Fix the export or the weights and run this command again.

- [ ] **Step 5: Commit**

```bash
git add .gitignore model-check/compare_models.py
git commit -m "feat: compare PyTorch and Core ML mole boxes"
```

Confirm `git status` does not list `model-check/images/` or `yolo26s-mole-800px.mlpackage`.
