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
