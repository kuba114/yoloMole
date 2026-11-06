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
