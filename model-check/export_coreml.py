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
