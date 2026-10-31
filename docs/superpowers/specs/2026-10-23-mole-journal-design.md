# Mole journal — version 1 design

Date: 2026-10-23

A native iPhone app for keeping a private photo log of named body areas. The person photographs an area in the same pose over time, an on-device copy of `yolo26s-mole-800px.pt` outlines moles, and the person compares the full photos. The app does not measure growth, diagnose, or recommend care.

## Product decisions

- Version 1 shows photos side by side. The person judges any change.
- A record is a body area, such as “left shoulder.” Each check-in is one photo of that whole area. The model outlines every mole it finds.
- The first check-in uses the camera with a short framing note. Later check-ins show the previous photo, then keep that photo at 40% opacity, aspect-fit and centered, over the live camera while the person matches the pose.
- Sign in with Apple unlocks the app. Photos stay on the phone. A second phone with the same Apple ID starts empty.
- Detection runs on the device from a Core ML export of `yolo26s-mole-800px.pt`. The phone does not call `yolo-api`.
- Boxes at confidence 0.30 or higher are kept. The label stored for each box is `Mole`. Confidence is stored and is not shown.
- Version 1 has no cloud backup, per-mole timelines, sharing, Android app, millimeter estimates, or clinical advice.

The sign-in screen includes this sentence: “A personal photo log of skin areas. It does not diagnose.”

## Journey

1. Sign in with Apple creates a local profile. Canceling sign-in stays on that screen.
2. The home screen lists body areas. An empty list asks the person to add one. The name is typed, trimmed, and must be non-empty. Two areas may share a name.
3. An area screen lists its check-ins, newest first.
4. The first check-in shows a framing note: fill the frame with the area, hold a steady distance, and use the same lighting next time. Then the camera opens with no faded photo.
5. A later check-in opens on the last saved photo and the words “Match this pose.” The camera then opens with that photo faded over the live view. The person can retake before the photo is saved. Leaving the camera before accepting the photo deletes the temporary image and adds nothing to the area.
6. After the person accepts the photo, the detector draws a box around every mole it finds. The person can hide or unhide a box on the review screen, and again later from that check-in. A hidden box stays stored and is omitted from comparison.
7. Comparison is available once an area has two check-ins. It opens the latest two full photos, with dates and the boxes that are still visible. The person can switch either side to another check-in of that same area. The two sides are always two different check-ins. One check-in has no comparison control.

Deleting the app deletes the journal. An in-app account deletion removes the Apple sign-in profile, the database, and every image file. Sign out returns to the sign-in screen and leaves the journal on disk, still bound to that Apple ID.

## Architecture

One SwiftUI app. Six parts:

| Part | Responsibility |
| --- | --- |
| Session gate | Shows Sign in with Apple until the local profile for this install is signed in. |
| Journal store | SwiftData records plus JPEG files in the app’s private folder. |
| Area list and area screen | Read the store and start a check-in or a comparison. |
| Capture flow | Framing note or previous-photo instruction, then the camera. Later check-ins draw the previous photo at 40% opacity. |
| Detector | Loads the bundled Core ML model, runs it on the accepted photo, and returns mole boxes. |
| Comparison | Draws two full photos and the boxes that are not hidden. |

The `.pt` file remains the reference model in this repository. A Python check exports it to Core ML and compares boxes on the same images before that Core ML file is added to the app. Inference uses the 800-pixel input size of the export. Boxes are mapped back onto the full saved image in the orientation the person saw.

Photos are saved as JPEG at quality 0.9. They are not copied to the Camera Roll.

## Stored data

One journal exists per install, bound to the first Apple ID that signs in. The store records that Apple user id.

**Body area:** id, trimmed name, created-at time.

**Check-in:** id, area id, capture time, image filename, pixel width, pixel height.

**Box:** id, check-in id, rectangle as fractions of the image (`x`, `y`, `width`, `height` from the top left), confidence, label `Mole`, hidden flag.

**Profile:** Apple user id, created-at time.

Saving a check-in writes the JPEG first, then the check-in and its boxes. If the record write fails, the JPEG is removed. The area never shows a photo without a record.

A different Apple ID sees a locked screen and cannot open the existing photos. Signing in again with the original Apple ID shows them. The app does not create a second journal on that phone.

Deleting one check-in removes its JPEG and boxes. Deleting an area removes every check-in under it. Deleting the account removes the profile, the SwiftData store, and the image folder.

## Failures

- Denying camera access closes the check-in and explains that the camera is required, with a link to Settings. The journal is unchanged.
- A photo with no boxes still saves.
- If the model fails to load or detection throws, the photo still saves and the review screen says “Outlines unavailable.”
- The detector runs on the image in the orientation the person saw, including photos the phone stores rotated.
- A full disk causes the save to fail, removes the temporary image, and leaves the area unchanged.
- Backgrounding or leaving before accept discards the temporary image.

## Testing

**Model gate, before the app screens.** A Python script runs `yolo26s-mole-800px.pt` and the exported Core ML model on the same still images. For each image it records the mole count and the box rectangles. A box matches when both labels are `Mole` and the intersection-over-union is at least 0.5. An image passes when the mole counts are equal and the boxes pair one-to-one. The Core ML file is bundled only after every image in a local set of close-up skin photos passes. Those photos stay on the developer machine and are not committed. Passing on `testvid.mp4` alone is not enough.

**Journal store, without the camera.** Tests create an area, reject an empty name, save a check-in with boxes, hide and unhide a box, delete a check-in, delete an area, and delete the account. A failed save leaves the area unchanged and leaves no JPEG behind. A second Apple user id cannot read the first id’s records.

**Detector.** A fixed image with a known orientation returns rectangles on the pixels the person sees, including a photo stored rotated. Inference input is 800 pixels on the model’s side, and the mapped boxes refer to the saved full-size image.

**Capture and comparison, on a device or simulator with fixture photos.** The first check-in has no faded guide. The second shows the last photo, then the faded guide. A photo with zero boxes still appears on the area. Comparison stays hidden until two check-ins exist, then shows the latest pair and omits hidden boxes. Denying the camera and canceling sign-in leave the journal unchanged.

**App Store pass, manual.** Sign in, add an area, take two matching photos, compare them, hide a box, delete the account, and confirm the photos are gone.

## Build order

1. Export `yolo26s-mole-800px.pt` to Core ML and pass the model gate on close-up skin photos.
2. Journal store and its tests.
3. Capture flow, detector, and comparison.
4. Sign in with Apple, the locked-journal rule, and account deletion.
5. Manual App Store pass.

## Out of scope

Cloud backup, sync across phones, per-mole timelines, sharing or PDF export, Android, millimeter measurement, growth scores, and any message that tells the person to seek care.
