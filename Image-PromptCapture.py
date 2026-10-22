import cv2

# ========== CONFIGURATION ==========
filename = "knifesheath.jpg"

# Open Mac webcam
cap = cv2.VideoCapture(0,cv2.CAP_AVFOUNDATION)

# Set resolution
#cap.set(cv2.CAP_PROP_FRAME_WIDTH, 800)
#cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 800)

# Make sure webcam opened
if not cap.isOpened():
    print("Error: Could not open webcam.")
    exit()

print("Reference Photo Capture Tool")
print("Position your object in the frame and press SPACE to capture")
print("Press ESC to exit")
print()

while True:
    # Capture CLEAN frame from webcam
    success, frame = cap.read()

    if not success:
        print("Error: Could not read frame.")
        break

    # Make a copy ONLY for displaying instructions
    display_frame = frame.copy()

    font = cv2.FONT_HERSHEY_SIMPLEX

    # Add instructions to display copy
    cv2.putText(
        display_frame,
        "SPACE: Take Photo | ESC: Exit",
        (10, 30),
        font,
        0.7,
        (255, 255, 255),
        2,
        cv2.LINE_AA
    )

    # Show frame with instructions
    cv2.imshow("Capture Reference Photo", display_frame)

    key = cv2.waitKey(1) & 0xFF

    # SPACE = save CLEAN photo
    if key == ord(" "):

        # Save original frame WITHOUT text
        cv2.imwrite(filename, frame)

        print(f"Photo saved: {filename}")

        # Confirmation is only displayed, not saved
        confirm_frame = frame.copy()

        cv2.putText(
            confirm_frame,
            f"Saved: {filename}",
            (10, 70),
            font,
            0.7,
            (0, 255, 0),
            2,
            cv2.LINE_AA
        )

        cv2.imshow("Capture Reference Photo", confirm_frame)

        # Show confirmation for 2 seconds
        cv2.waitKey(2000)

    # ESC = exit
    elif key == 27:
        break

# Release webcam
cap.release()

# Close windows
cv2.destroyAllWindows()

