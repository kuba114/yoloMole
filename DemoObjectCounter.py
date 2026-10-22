import cv2
from ultralytics import YOLO

# ========== CONFIGURATION ==========
TARGET_OBJECT = "red and green flower"
TARGET_COUNT = 2
CONFIDENCE_THRESHOLD = 0.2

# ========== OPEN MAC WEBCAM ==========
cap = cv2.VideoCapture(0, cv2.CAP_AVFOUNDATION)

if not cap.isOpened():
    print("Error: Could not open webcam.")
    exit()

print("Webcam opened successfully")

# ========== LOAD YOLOE MODEL ==========
model = YOLO("yoloe-11s-test1-seg.onnx")

# Get class names
class_names = model.names

print(f"Looking for {TARGET_COUNT} {TARGET_OBJECT}(s)")
print(f"Minimum confidence: {CONFIDENCE_THRESHOLD}")
print("Press 'q' to quit")

# ========== MAIN LOOP ==========
while True:

    # Capture frame from Mac webcam
    success, frame = cap.read()

    if not success:
        print("Error: Could not read frame.")
        break

    # Run YOLOE
    results = model.predict(
        frame,
        verbose=False
    )

    # Count objects
    object_count = 0
    confident_objects = []

    if results[0].boxes is not None:

        detected_classes = results[0].boxes.cls.cpu().numpy()
        confidences = results[0].boxes.conf.cpu().numpy()

        for i, class_id in enumerate(detected_classes):

            class_name = class_names[int(class_id)]
            confidence = confidences[i]

            if (
                class_name.lower() == TARGET_OBJECT.lower()
                and confidence >= CONFIDENCE_THRESHOLD
            ):
                object_count += 1

                confident_objects.append({
                    "class_name": class_name,
                    "confidence": confidence
                })

    # ========== ACTION TRIGGER ==========
    if object_count >= TARGET_COUNT:

        print(
            f"Target number of objects detected! "
            f"({object_count} confident {TARGET_OBJECT}(s))"
        )

        for i, obj in enumerate(confident_objects):

            print(
                f"{TARGET_OBJECT} #{i+1}: "
                f"{obj['confidence']:.3f} confidence"
            )

        # ADD CUSTOM ACTION HERE
        #
        # Example:
        # send notification
        # save image
        # trigger another program
        # etc.

    # ========== DRAW DETECTIONS ==========
    annotated_frame = results[0].plot(
        boxes=True,
        masks=False
    )

    # Calculate FPS
    inference_time = results[0].speed["inference"]

    fps = (
        1000 / inference_time
        if inference_time > 0
        else 0
    )

    # Status text
    status_text = (
        f"Looking for: {TARGET_COUNT} {TARGET_OBJECT}(s) | "
        f"Found: {object_count} | "
        f"FPS: {fps:.1f} | "
        f"Min Conf: {CONFIDENCE_THRESHOLD}"
    )

    font = cv2.FONT_HERSHEY_SIMPLEX

    cv2.putText(
        annotated_frame,
        status_text,
        (10, 30),
        font,
        0.7,
        (0, 255, 0),
        2,
        cv2.LINE_AA
    )

    # Target reached
    if object_count >= TARGET_COUNT:

        cv2.putText(
            annotated_frame,
            "TARGET REACHED!",
            (10, 70),
            font,
            1,
            (0, 255, 0),
            3,
            cv2.LINE_AA
        )

        # Display confidence
        for i, obj in enumerate(confident_objects):

            conf_text = (
                f"{TARGET_OBJECT} #{i+1}: "
                f"{obj['confidence']:.2f}"
            )

            cv2.putText(
                annotated_frame,
                conf_text,
                (10, 110 + i * 30),
                font,
                0.6,
                (0, 255, 255),
                2,
                cv2.LINE_AA
            )

    # ========== DISPLAY ==========
    cv2.imshow(
        "YOLOE Object Counter",
        annotated_frame
    )

    # Q to quit
    if cv2.waitKey(1) & 0xFF == ord("q"):
        break


# ========== CLEANUP ==========
cap.release()
cv2.destroyAllWindows()
