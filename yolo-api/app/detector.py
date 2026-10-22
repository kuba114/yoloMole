import cv2
from ultralytics import YOLO
import subprocess
import os

MODELS = {
    'small': 'models/yoloe-11s-part-seg.onnx',
    'medium': 'models/yoloe-11m-part-seg.onnx',
    'large': 'models/yoloe-11l-part-seg.onnx'
}
def process_video(input_path,output_path,model_name):
    if model_name not in MODELS:
        raise ValueError(f"Invalid model name. Choose from: {list(MODELS.keys())}")
    model = YOLO(MODELS[model_name])
    cap = cv2.VideoCapture(input_path)
    if not cap.isOpened():
        raise ValueError(f"Error: Could not open video file {input_path}.")
    # Get original video properties
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS)

    if fps <= 0:
        fps = 30

    #Create Temporary output path
    temp_output_path = output_path.replace(".mp4", "_temp.mp4")
    # Create output video
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")

    writer = cv2.VideoWriter(
        temp_output_path,
        fourcc,
        fps,
        (width, height)
    )
    if not writer.isOpened():
        cap.release()
        raise ValueError("Error: Could not create output video.")
    while True:

        success, frame = cap.read()

        if not success:
            break

        # Run YOLOE detection
        results = model.predict(
            frame,
            verbose=False
        )

        # Draw detections
        annotated_frame = results[0].plot(
            boxes=True,
            masks=False
        )

        # Get model inference time
        inference_time = results[0].speed["inference"]

        if inference_time > 0:
            model_fps = 1000 / inference_time
        else:
            model_fps = 0

        text = f"FPS: {model_fps:.1f}"

        font = cv2.FONT_HERSHEY_SIMPLEX

        text_size = cv2.getTextSize(
            text,
            font,
            1,
            2
        )[0]

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
            cv2.LINE_AA
        )

        # Save frame to output video
        writer.write(annotated_frame)

    cap.release()
    writer.release()
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-i", temp_output_path,
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            output_path
        ],
        check=True
    )
    os.remove(temp_output_path)
    return output_path