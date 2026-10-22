import cv2
from ultralytics import YOLO

# ========== CONFIGURATION ==========
TARGET_OBJECT = "red and green flower"
CONFIDENCE_THRESHOLD = 0.2

# ========== OPEN MAC WEBCAM ==========
cap = cv2.VideoCapture(0, cv2.CAP_AVFOUNDATION)

if not cap.isOpened():
    print("Error: Could not open webcam.")
    exit()

print("Webcam opened successfully")

# ========== LOAD YOLOE MODEL ==========
model = YOLO("yoloe-11s-test1-seg.onnx")
class_names = model.names

print(f"Tracking location of: {TARGET_OBJECT}")
print(f"Minimum confidence: {CONFIDENCE_THRESHOLD}")
print("Press 'q' to quit")

# ========== MAIN LOOP ==========
while True:

    # Capture frame from webcam
    success, frame = cap.read()

    if not success:
        print("Error: Could not read frame.")
        break

    # Get frame dimensions
    frame_height, frame_width = frame.shape[:2]

    # Run YOLOE
    results = model.predict(
        frame,
        verbose=False
    )

    # Store detected object locations
    object_locations = []

    if results[0].boxes is not None:

        # Get bounding boxes
        boxes = results[0].boxes.xyxy.cpu().numpy()

        # Get detected class IDs
        detected_classes = results[0].boxes.cls.cpu().numpy()

        # Get confidence scores
        confidences = results[0].boxes.conf.cpu().numpy()

        # Process each detected object
        for i, class_id in enumerate(detected_classes):

            class_name = class_names[int(class_id)]
            confidence = confidences[i]

            # Check target object and confidence
            if (
                class_name.lower() == TARGET_OBJECT.lower()
                and confidence >= CONFIDENCE_THRESHOLD
            ):

                # Bounding box coordinates
                x1, y1, x2, y2 = boxes[i]

                # Calculate center
                center_x = (x1 + x2) / 2
                center_y = (y1 + y2) / 2

                # Relative coordinates
                relative_x = center_x / frame_width
                relative_y = center_y / frame_height

                object_locations.append({
                    "x": relative_x,
                    "y": relative_y,
                    "pixel_x": int(center_x),
                    "pixel_y": int(center_y),
                    "confidence": confidence
                })

    # ========== ACTION TRIGGER ==========
    for i, location in enumerate(object_locations):

        confidence = location["confidence"]

        print(
            f"{TARGET_OBJECT} #{i+1} at relative position: "
            f"({location['x']:.3f}, {location['y']:.3f}) "
            f"- Confidence: {confidence:.3f}"
        )

        # Bottom-right area of image
        if location["x"] > 0.5 and location["y"] > 0.5:

            print(
                f"{TARGET_OBJECT} detected in bottom right corner! "
                f"(Confidence: {confidence:.3f})"
            )

            # ADD CUSTOM ACTION HERE

    # ========== DRAW DETECTIONS ==========
    annotated_frame = results[0].plot(
        boxes=True,
        masks=False
    )

    # Draw center points and coordinates
    for location in object_locations:

        px = location["pixel_x"]
        py = location["pixel_y"]

        rx = location["x"]
        ry = location["y"]

        confidence = location["confidence"]

        # Center dot
        cv2.circle(
            annotated_frame,
            (px, py),
            5,
            (0, 255, 255),
            -1
        )

        # Coordinate text
        coord_text = (
            f"({rx:.2f}, {ry:.2f}) "
            f"{confidence:.2f}"
        )

        cv2.putText(
            annotated_frame,
            coord_text,
            (px + 10, py - 10),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (0, 255, 255),
            1,
            cv2.LINE_AA
        )

    # ========== FPS ==========
    inference_time = results[0].speed["inference"]

    fps = (
        1000 / inference_time
        if inference_time > 0
        else 0
    )

    # Status text
    status_text = (
        f"Tracking: {TARGET_OBJECT} | "
        f"Found: {len(object_locations)} | "
        f"FPS: {fps:.1f} | "
        f"Min Conf: {CONFIDENCE_THRESHOLD}"
    )

    cv2.putText(
        annotated_frame,
        status_text,
        (10, 30),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.7,
        (0, 255, 0),
        2,
        cv2.LINE_AA
    )

    # ========== DISPLAY ==========
    cv2.imshow(
        "YOLOE Object Location Tracker",
        annotated_frame
    )

    # Q to quit
    if cv2.waitKey(1) & 0xFF == ord("q"):
        break


# ========== CLEANUP ==========
cap.release()
cv2.destroyAllWindows()
