# On-device SAHI slicing

Date: 2026-11-06

New check-ins on the iPhone run the bundled Core ML mole model on overlapping 800×800 slices of the upright photo, then merge the boxes with SAHI’s greedy non-maximum merging. The phone does not call the SAHI Python package. Saved check-ins are not detected again. The crop handles still move the boxes from that one pass and do not run the model again.

This replaces the capture threshold in the version 1 journal design. A new photo keeps a Mole box at confidence 0.40 or higher. The Python model gate stays at 0.30 and is unchanged.

## Settings

These match the requested `get_sliced_prediction` call.

| Setting | Value |
| --- | --- |
| Slice width and height | 800 |
| Overlap width and height | 0.20 |
| Full-image prediction | Off (`perform_standard_pred=False`) |
| Merge | GREEDYNMM |
| Match metric | IOU |
| Match threshold | 0.5 |
| Class-agnostic merge | Off |
| Confidence | 0.40 |
| Kept class | Mole, class id 1 |

SAHI’s current default match metric is IOS. This design uses IOU because the request sets `postprocess_match_metric="IOU"`. Confidence 0.40 is above SAHI’s 0.1 cutoff, so the merge stays GREEDYNMM and does not switch to NMS.

Overlap in pixels is `int(0.20 × 800) = 160`. The step from one window origin to the next is 640.

## Slice windows

`sliceWindows(imageWidth:imageHeight:)` copies `get_slice_bboxes` from SAHI when both slice sizes are provided.

- Start at the top left.
- A window that would pass the right or bottom edge is pulled back so its far edge lies on the image edge and its size stays 800, unless the image itself is smaller than 800 on that side.
- The next origin is the previous far edge minus 160.
- Windows are returned in that loop order, left to right, then top to bottom. Coordinates are pixels of the upright photo, with the origin at the top left.

Examples:

- 800×800 returns one window, `[0, 0, 800, 800]`.
- 400×400 returns one window, `[0, 0, 400, 400]`.
- 1000×800 returns `[0, 0, 800, 800]` and `[200, 0, 1000, 800]`.
- 4032×3024 returns 35 windows. The first is `[0, 0, 800, 800]`. The last is `[3232, 2224, 4032, 3024]`. Every window is 800×800.

When both image sides are at least 800, every window is exactly 800×800. A shorter side produces a window of that image side.

## Prediction

`CoreMLMoleDetector.detect` keeps the same `MoleDetecting` entry point. Capture does not change its call.

For each window:

1. Crop the upright image to the window.
2. Letterbox that crop to the model input with the existing placement and gray value 114. An 800×800 crop has no padding and a gain of 1.
3. Run the existing end-to-end Core ML read. A row is kept when it has six values, the score is at least 0.40, and the rounded class id is 1.
4. Map the box from model space back onto the crop with the existing letterbox scale, then add the window’s left and top to place it on the full photo.

Slices run one at a time. A 4032×3024 photo is 35 model runs. The review screen appears after the full set finishes. There is no progress control.

If the model is missing, the JPEG cannot be read, a crop cannot be made, or any slice throws, the outcome is no boxes and `outlinesUnavailable`. Partial boxes from earlier slices are discarded. A photo with zero boxes still saves, and the review screen still says outlines are unavailable only when detection failed.

## Merge

After every slice, `greedyNMM` merges the kept Mole boxes.

1. Sort by score descending. Equal scores sort by `x1`, then `y1`, then `x2`, then `y2`, all ascending.
2. Take the next box that has not been merged into an earlier box. It is a keeper.
3. Among the later boxes that are still free, take those whose IoU with the keeper’s original rectangle is at least 0.5. That comparison uses the keeper before any union.
4. Walk those matches from highest score to lowest. Union a match into the keeper only when its IoU with the keeper’s current rectangle is still at least 0.5. The union is the smallest rectangle that contains both. The score becomes the higher of the two scores.
5. A match that fails that second check is dropped. It is not returned as its own box.
6. A box that never overlaps a keeper at 0.5 or more stays as its own box.

IoU is intersection area divided by the sum of the two areas minus the intersection. Boxes touch at a threshold of exactly 0.5.

Greedy merging does not chain through a third box. In this set, A overlaps B and A overlaps C, while B does not have to overlap C:

- A `[5, 0, 15, 10]` score 0.90
- B `[0, 0, 14, 10]` score 0.80, IoU with A is 0.60
- C `[7, 0, 17, 10]` score 0.70, IoU with A is 2/3

A merges with B first. The union is `[0, 0, 15, 10]` with score 0.90. C’s IoU with that union is 80/170, which is below 0.5, so C is dropped. The result is the one union box.

Two boxes below an IoU of 0.5 both remain. Their scores and rectangles are unchanged.

The merged rectangles are stored as fractions of the full upright photo, with label `Mole` and the merged score. Numbering, hiding, comparison, and cropping use those boxes as they do today.

## Testing

Tests in `SlicePredictionTests` do not load Core ML.

- Window lists for 800×800, 400×400, 1000×800, and the first and last window of 4032×3024, including the count 35.
- A box inside a window shifts by that window’s origin.
- Score 0.39 and any class other than 1 are dropped. Score 0.40 and class 1 are kept.
- The A, B, and C case above yields only `[0, 0, 15, 10]` at score 0.90.
- Two disjoint boxes both remain.
- Two overlapping boxes with the same score merge into the one with the smaller `x1`. The merged score stays that shared score, and the rectangle is their union.

## Out of scope

The Python camera scripts, `model-check/compare_models.py`, re-detection of saved photos, a second detection after cropping, and a slice progress indicator.
