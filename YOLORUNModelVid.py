import cv2
from ultralytics import YOLO

# Open video file
video_path = "testvid.mp4"
cap = cv2.VideoCapture(video_path)

# Make sure video opened successfully
if not cap.isOpened():
    print(f"Error: Could not open video: {video_path}")
    exit()

# Load YOLO model
model = YOLO("yolo26s-mole-800px.pt")

while True:
    # Read a frame from the video
    success, frame = cap.read()

    # End of video
    if not success:
        print("Video processing complete.")
        break

    # Run inference
    results = model.predict(frame, verbose=False,conf = 0.3)

    # Draw detections
    annotated_frame = results[0].plot(boxes=True, masks=False)

    # Calculate FPS
    inference_time = results[0].speed["inference"]
    fps = 1000 / inference_time if inference_time > 0 else 0

    text = f"FPS: {fps:.1f}"

    # Draw FPS text
    font = cv2.FONT_HERSHEY_SIMPLEX
    text_size = cv2.getTextSize(text, font, 1, 2)[0]
    text_x = annotated_frame.shape[1] - text_size[0] - 10
    text_y = text_size[1] + 10

    cv2.putText(
        annotated_frame,
        text,
        (text_x, text_y),
        font,
        1,
        (255, 255, 255),
        2,
        cv2.LINE_AA,
    )

    # Show frame
    cv2.imshow("YOLO Video Detection", annotated_frame)

    # Press q to quit early
    if cv2.waitKey(1) & 0xFF == ord("q"):
        break

# Cleanup
cap.release()
cv2.destroyAllWindows()
