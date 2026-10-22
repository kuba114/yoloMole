import cv2
from ultralytics import YOLO

#open Mac webcam
cap = cv2.VideoCapture(0)

#Set webcam resolution
cap.set(cv2.CAP_PROP_FRAME_WIDTH, 800)
cap.set(cv2.CAP_PROP_FRAME_HEIGHT,800)

#Make sure camera opened successfully
if not cap.isOpened():
    print("Error: Could not open webcam.")
    exit()

# Load YOLOE prompt-free model
model = YOLO("yolo26s-mole-800px.pt")

while True:
    # Capture a frame 
    success, frame = cap.read()

    if not success:
        print("Error: could not read frame.")
        break
    # Run YOLOE model on the captured fram
    results = model.predict(frame,verbose=False,conf=0.30)
    
    # Output the visual detection data
    annotated_frame = results[0].plot(boxes=True, masks=False)
    
    # Get inference time
    inference_time = results[0].speed['inference']
    fps = 1000 / inference_time  # Convert to milliseconds
    text = f'FPS: {fps:.1f}'
    
    # Define font and position
    font = cv2.FONT_HERSHEY_SIMPLEX
    text_size = cv2.getTextSize(text, font, 1, 2)[0]
    text_x = annotated_frame.shape[1] - text_size[0] - 10  # 10 pixels from the right
    text_y = text_size[1] + 10  # 10 pixels from the top
    
    # Draw the text on the annotated frame
    cv2.putText(annotated_frame, text, (text_x, text_y), font, 1, (255, 255, 255), 2, cv2.LINE_AA)
    
    # Display the resulting frame
    cv2.imshow("Camera", annotated_frame)
    
    # Exit the program if q is pressed
    if cv2.waitKey(1) == ord("q"):
        break

# Close all windows
cap.release()
cv2.destroyAllWindows()
