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
