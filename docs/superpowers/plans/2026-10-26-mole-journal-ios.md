# Mole Journal iOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a phone-only iPhone journal where a person photographs named body areas in the same pose, sees on-device Mole boxes, and compares the full photos.

**Architecture:** One SwiftUI application stores SwiftData records and JPEG files in the app sandbox. Capture and comparison rules are pure functions covered by unit tests. A Core ML detector runs after the person accepts a photo. Sign in with Apple unlocks the single journal on that install.

**Tech Stack:** Xcode 16, iOS 17, SwiftUI, SwiftData, Core ML, Vision, AuthenticationServices, XcodeGen, `xcodebuild`.

This plan starts after `docs/superpowers/plans/2026-10-26-coreml-model-gate.md` has produced `yolo26s-mole-800px.mlpackage` on a Mac. The iPhone app does not call `yolo-api`.

## Global Constraints

- Version 1 shows photos side by side. The person judges any change.
- A record is a body area. Each check-in is one photo of that whole area.
- The first check-in uses the camera with the framing note. Later check-ins show the previous photo, then keep that photo at 40% opacity, aspect-fit and centered, over the live camera.
- Sign in with Apple unlocks the app. Photos stay on the phone. A second phone with the same Apple ID starts empty.
- One journal exists per install, bound to the first Apple ID that signs in.
- A different Apple ID sees a locked screen and cannot open the existing photos.
- Detection uses the Core ML export of `yolo26s-mole-800px.pt` at 800 pixels. Boxes at confidence 0.30 or higher are kept. The label is `Mole`. Confidence is stored and is not shown.
- Photos are JPEG at quality 0.9. They are not copied to the Camera Roll.
- A photo with no boxes still saves. A failed model still saves and shows `Outlines unavailable`.
- The sign-in sentence is `A personal photo log of skin areas. It does not diagnose.`
- The later-check-in sentence is `Match this pose.`
- The first-check-in sentence is `Fill the frame with the area, hold a steady distance, and use the same lighting next time.`
- The camera sentence is `The camera is required to photograph a body area.`
- The locked-journal sentence is `This phone's journal belongs to a different Apple ID.`
- The unavailable-outline sentence is `Outlines unavailable`.
- Version 1 has no cloud backup, per-mole timelines, sharing, Android app, millimeter estimates, or clinical advice.

---

### Task 1: App shell and the sign-in sentence

**Files:**
- Create: `ios/project.yml`
- Create: `ios/MoleJournal/MoleJournal.entitlements`
- Create: `ios/MoleJournal/Copy.swift`
- Create: `ios/MoleJournal/MoleJournalApp.swift`
- Test: `ios/MoleJournalTests/CopyTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `enum Copy` with `signInDisclaimer`, `matchPose`, `framingNote`, `cameraRequired`, `outlinesUnavailable`, and `lockedJournal`. Scheme `MoleJournal` builds for the iOS Simulator.

- [ ] **Step 1: Write the failing test**

Create `ios/MoleJournalTests/CopyTests.swift`:

```swift
import XCTest
@testable import MoleJournal

final class CopyTests: XCTestCase {
    func testSignInDisclaimer() {
        XCTAssertEqual(
            Copy.signInDisclaimer,
            "A personal photo log of skin areas. It does not diagnose."
        )
    }

    func testPoseAndFailureCopy() {
        XCTAssertEqual(Copy.matchPose, "Match this pose.")
        XCTAssertEqual(
            Copy.framingNote,
            "Fill the frame with the area, hold a steady distance, and use the same lighting next time."
        )
        XCTAssertEqual(
            Copy.cameraRequired,
            "The camera is required to photograph a body area."
        )
        XCTAssertEqual(Copy.outlinesUnavailable, "Outlines unavailable")
        XCTAssertEqual(
            Copy.lockedJournal,
            "This phone's journal belongs to a different Apple ID."
        )
    }
}
```

- [ ] **Step 2: Add the XcodeGen project and run the test to verify it fails**

Create `ios/project.yml`:

```yaml
name: MoleJournal
options:
  bundleIdPrefix: com.yolomole
  deploymentTarget:
    iOS: "17.0"
settings:
  SWIFT_VERSION: "5.0"
  IPHONEOS_DEPLOYMENT_TARGET: "17.0"
targets:
  MoleJournal:
    type: application
    platform: iOS
    sources:
      - MoleJournal
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.yolomole.MoleJournal
      GENERATE_INFOPLIST_FILE: YES
      INFOPLIST_KEY_NSCameraUsageDescription: "The camera is required to photograph a body area."
      INFOPLIST_KEY_UILaunchScreen_Generation: YES
      CODE_SIGN_ENTITLEMENTS: MoleJournal/MoleJournal.entitlements
      TARGETED_DEVICE_FAMILY: "1"
  MoleJournalTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - MoleJournalTests
    dependencies:
      - target: MoleJournal
    settings:
      GENERATE_INFOPLIST_FILE: YES
      TEST_HOST: "$(BUILT_PRODUCTS_DIR)/MoleJournal.app/MoleJournal"
      BUNDLE_LOADER: "$(TEST_HOST)"
```

Create `ios/MoleJournal/MoleJournal.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.developer.applesignin</key>
  <array>
    <string>Default</string>
  </array>
</dict>
</plist>
```

Create a temporary `ios/MoleJournal/MoleJournalApp.swift` so the app target compiles before `Copy` exists:

```swift
import SwiftUI

@main
struct MoleJournalApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Mole Journal")
        }
    }
}
```

Run:

```bash
cd ios
xcodegen generate
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests/CopyTests
```

Expected: FAIL because `Copy` is not defined. If the simulator name is unavailable, run `xcodebuild -project MoleJournal.xcodeproj -scheme MoleJournal -showdestinations` and use an available iPhone simulator for every later `xcodebuild` command in this plan.

- [ ] **Step 3: Add the copy and show it on the sign-in screen**

Create `ios/MoleJournal/Copy.swift`:

```swift
enum Copy {
    static let signInDisclaimer = "A personal photo log of skin areas. It does not diagnose."
    static let matchPose = "Match this pose."
    static let framingNote = "Fill the frame with the area, hold a steady distance, and use the same lighting next time."
    static let cameraRequired = "The camera is required to photograph a body area."
    static let outlinesUnavailable = "Outlines unavailable"
    static let lockedJournal = "This phone's journal belongs to a different Apple ID."
}
```

Replace `ios/MoleJournal/MoleJournalApp.swift` with:

```swift
import SwiftUI

@main
struct MoleJournalApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Text(Copy.signInDisclaimer)
                    .multilineTextAlignment(.center)
                Text("Sign in with Apple")
            }
            .padding()
        }
    }
}
```

The real Sign in with Apple button arrives in Task 8. This task only locks the sentence into the first screen.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests/CopyTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/project.yml ios/MoleJournal/MoleJournal.entitlements ios/MoleJournal/Copy.swift ios/MoleJournal/MoleJournalApp.swift ios/MoleJournalTests/CopyTests.swift ios/MoleJournal.xcodeproj
git commit -m "feat: start the mole journal app shell"
```

---

### Task 2: Capture and comparison rules

**Files:**
- Create: `ios/MoleJournal/JournalRules.swift`
- Test: `ios/MoleJournalTests/JournalRulesTests.swift`

**Interfaces:**
- Consumes: `Copy.matchPose`, `Copy.framingNote`
- Produces:
  - `struct CaptureStep` with `phase` (`.instruction`, `.camera`, `.review`), `previousImageFilename: String?`, `instruction: String`, `showsGhost: Bool`
  - `func initialCaptureStep(previousImageFilename: String?) -> CaptureStep`
  - `func advanceToCamera(_ step: CaptureStep) -> CaptureStep`
  - `struct ComparisonSelection` with `leftID: UUID` and `rightID: UUID`
  - `func defaultComparison(newestFirst: [UUID]) -> ComparisonSelection?`
  - `func visibleBoxes(_ boxes: [MoleBoxDraft]) -> [MoleBoxDraft]`
  - `struct MoleBoxDraft` with `x`, `y`, `width`, `height`, `confidence`, `label`, `hidden`

- [ ] **Step 1: Write the failing test**

Create `ios/MoleJournalTests/JournalRulesTests.swift`:

```swift
import XCTest
@testable import MoleJournal

final class JournalRulesTests: XCTestCase {
    func testFirstCheckInHasNoGhost() {
        let step = initialCaptureStep(previousImageFilename: nil)
        XCTAssertEqual(step.instruction, Copy.framingNote)
        XCTAssertNil(step.previousImageFilename)
        let camera = advanceToCamera(step)
        XCTAssertEqual(camera.phase, .camera)
        XCTAssertFalse(camera.showsGhost)
    }

    func testLaterCheckInShowsPreviousPhotoThenGhost() {
        let step = initialCaptureStep(previousImageFilename: "last.jpg")
        XCTAssertEqual(step.phase, .instruction)
        XCTAssertEqual(step.instruction, Copy.matchPose)
        XCTAssertFalse(step.showsGhost)
        let camera = advanceToCamera(step)
        XCTAssertTrue(camera.showsGhost)
        XCTAssertEqual(camera.previousImageFilename, "last.jpg")
    }

    func testComparisonNeedsTwoDifferentCheckIns() {
        let only = UUID()
        XCTAssertNil(defaultComparison(newestFirst: [only]))
        let newest = UUID()
        let older = UUID()
        let pair = defaultComparison(newestFirst: [newest, older])
        XCTAssertEqual(pair?.leftID, newest)
        XCTAssertEqual(pair?.rightID, older)
        XCTAssertNotEqual(pair?.leftID, pair?.rightID)
    }

    func testHiddenBoxesAreOmitted() {
        let shown = MoleBoxDraft(x: 0, y: 0, width: 0.1, height: 0.1, confidence: 0.4, label: "Mole", hidden: false)
        let hidden = MoleBoxDraft(x: 0.2, y: 0.2, width: 0.1, height: 0.1, confidence: 0.8, label: "Mole", hidden: true)
        XCTAssertEqual(visibleBoxes([shown, hidden]), [shown])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests/JournalRulesTests
```

Expected: FAIL because `initialCaptureStep` is not defined.

- [ ] **Step 3: Write the rules**

Create `ios/MoleJournal/JournalRules.swift`:

```swift
import Foundation

struct MoleBoxDraft: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var confidence: Double
    var label: String
    var hidden: Bool
}

struct CaptureStep: Equatable {
    enum Phase: Equatable {
        case instruction
        case camera
        case review
    }

    var phase: Phase
    var previousImageFilename: String?
    var instruction: String
    var showsGhost: Bool
}

func initialCaptureStep(previousImageFilename: String?) -> CaptureStep {
    if let previousImageFilename {
        return CaptureStep(
            phase: .instruction,
            previousImageFilename: previousImageFilename,
            instruction: Copy.matchPose,
            showsGhost: false
        )
    }
    return CaptureStep(
        phase: .instruction,
        previousImageFilename: nil,
        instruction: Copy.framingNote,
        showsGhost: false
    )
}

func advanceToCamera(_ step: CaptureStep) -> CaptureStep {
    var next = step
    next.phase = .camera
    next.showsGhost = step.previousImageFilename != nil
    return next
}

struct ComparisonSelection: Equatable {
    var leftID: UUID
    var rightID: UUID
}

func defaultComparison(newestFirst: [UUID]) -> ComparisonSelection? {
    guard newestFirst.count >= 2 else { return nil }
    return ComparisonSelection(leftID: newestFirst[0], rightID: newestFirst[1])
}

func visibleBoxes(_ boxes: [MoleBoxDraft]) -> [MoleBoxDraft] {
    boxes.filter { !$0.hidden }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests/JournalRulesTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/MoleJournal/JournalRules.swift ios/MoleJournalTests/JournalRulesTests.swift
git commit -m "feat: define capture and comparison rules"
```

---

### Task 3: Journal store

**Files:**
- Create: `ios/MoleJournal/JournalStore.swift`
- Test: `ios/MoleJournalTests/JournalStoreTests.swift`

**Interfaces:**
- Consumes: `MoleBoxDraft`
- Produces: `enum JournalError` (`.emptyName`, `.saveFailed`, `.wrongAppleID`, `.notFound`), `enum SessionState` (`.signedOut`, `.signedIn`, `.locked`), and `final class JournalStore` with:
  - `init(context: ModelContext, imageDirectory: URL)`
  - `var failNextSave: Bool` — when true, the next `saveCheckIn` record write throws `JournalError.saveFailed` and the flag clears. `beginSession` and `createArea` ignore it.
  - `func beginSession(appleUserID: String, now: Date) throws -> SessionState`
  - `func endSession()`
  - `func restoreSession() -> SessionState`
  - `func createArea(name: String, now: Date) throws -> BodyAreaRecord`
  - `func areas(sessionAppleID: String) throws -> [BodyAreaRecord]`
  - `func saveCheckIn(areaID: UUID, sessionAppleID: String, jpeg: Data, pixelWidth: Int, pixelHeight: Int, boxes: [MoleBoxDraft], capturedAt: Date) throws -> CheckInRecord`
  - `func checkIns(areaID: UUID, sessionAppleID: String) throws -> [CheckInRecord]`
  - `func setBoxHidden(boxID: UUID, sessionAppleID: String, hidden: Bool) throws`
  - `func deleteCheckIn(id: UUID, sessionAppleID: String) throws`
  - `func deleteArea(id: UUID, sessionAppleID: String) throws`
  - `func deleteAccount() throws`
  - `func imageURL(filename: String) -> URL`

- [ ] **Step 1: Write the failing test**

Create `ios/MoleJournalTests/JournalStoreTests.swift`:

```swift
import XCTest
import SwiftData
@testable import MoleJournal

final class JournalStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() throws -> JournalStore {
        let schema = Schema([
            ProfileRecord.self,
            BodyAreaRecord.self,
            CheckInRecord.self,
            MoleBoxRecord.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return JournalStore(
            context: ModelContext(container),
            imageDirectory: directory
        )
    }

    func testEmptyNameIsRejected() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.beginSession(appleUserID: "apple-a", now: Date()), .signedIn)
        XCTAssertThrowsError(try store.createArea(name: "   ", now: Date())) { error in
            XCTAssertEqual(error as? JournalError, .emptyName)
        }
    }

    func testTrimmedDuplicateNamesAreKept() throws {
        let store = try makeStore()
        _ = try store.beginSession(appleUserID: "apple-a", now: Date())
        _ = try store.createArea(name: " left shoulder ", now: Date(timeIntervalSince1970: 10))
        _ = try store.createArea(name: "left shoulder", now: Date(timeIntervalSince1970: 20))
        let names = try store.areas(sessionAppleID: "apple-a").map(\.name)
        XCTAssertEqual(names, ["left shoulder", "left shoulder"])
    }

    func testSaveHideAndDeleteCheckIn() throws {
        let store = try makeStore()
        _ = try store.beginSession(appleUserID: "apple-a", now: Date())
        let area = try store.createArea(name: "arm", now: Date())
        let box = MoleBoxDraft(
            x: 0.1, y: 0.2, width: 0.3, height: 0.4,
            confidence: 0.55, label: "Mole", hidden: false
        )
        let checkIn = try store.saveCheckIn(
            areaID: area.id,
            sessionAppleID: "apple-a",
            jpeg: Data("jpeg".utf8),
            pixelWidth: 800,
            pixelHeight: 600,
            boxes: [box],
            capturedAt: Date(timeIntervalSince1970: 30)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.imageURL(filename: checkIn.imageFilename).path))
        let savedBox = try XCTUnwrap(checkIn.boxes.first)
        try store.setBoxHidden(boxID: savedBox.id, sessionAppleID: "apple-a", hidden: true)
        let hidden = try XCTUnwrap(store.checkIns(areaID: area.id, sessionAppleID: "apple-a").first?.boxes.first)
        XCTAssertTrue(hidden.hidden)
        try store.setBoxHidden(boxID: savedBox.id, sessionAppleID: "apple-a", hidden: false)
        let shown = try XCTUnwrap(store.checkIns(areaID: area.id, sessionAppleID: "apple-a").first?.boxes.first)
        XCTAssertFalse(shown.hidden)
        try store.deleteCheckIn(id: checkIn.id, sessionAppleID: "apple-a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(filename: checkIn.imageFilename).path))
        XCTAssertTrue(try store.checkIns(areaID: area.id, sessionAppleID: "apple-a").isEmpty)
    }

    func testCheckInsAreNewestFirst() throws {
        let store = try makeStore()
        _ = try store.beginSession(appleUserID: "apple-a", now: Date())
        let area = try store.createArea(name: "arm", now: Date())
        _ = try store.saveCheckIn(
            areaID: area.id, sessionAppleID: "apple-a", jpeg: Data([1]),
            pixelWidth: 1, pixelHeight: 1, boxes: [],
            capturedAt: Date(timeIntervalSince1970: 10)
        )
        _ = try store.saveCheckIn(
            areaID: area.id, sessionAppleID: "apple-a", jpeg: Data([2]),
            pixelWidth: 1, pixelHeight: 1, boxes: [],
            capturedAt: Date(timeIntervalSince1970: 20)
        )
        let times = try store.checkIns(areaID: area.id, sessionAppleID: "apple-a").map(\.capturedAt)
        XCTAssertEqual(times, [Date(timeIntervalSince1970: 20), Date(timeIntervalSince1970: 10)])
    }

    func testFailedSaveLeavesNoFileOrRecord() throws {
        let store = try makeStore()
        _ = try store.beginSession(appleUserID: "apple-a", now: Date())
        let area = try store.createArea(name: "arm", now: Date())
        store.failNextSave = true
        XCTAssertThrowsError(
            try store.saveCheckIn(
                areaID: area.id, sessionAppleID: "apple-a", jpeg: Data([9]),
                pixelWidth: 2, pixelHeight: 2, boxes: [],
                capturedAt: Date()
            )
        )
        let leftovers = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertTrue(leftovers.filter { $0.pathExtension == "jpg" }.isEmpty)
        XCTAssertTrue(try store.checkIns(areaID: area.id, sessionAppleID: "apple-a").isEmpty)
    }

    func testSecondAppleIDCannotRead() throws {
        let store = try makeStore()
        _ = try store.beginSession(appleUserID: "apple-a", now: Date())
        _ = try store.createArea(name: "arm", now: Date())
        XCTAssertEqual(try store.beginSession(appleUserID: "apple-b", now: Date()), .locked)
        XCTAssertEqual(store.restoreSession(), .signedOut)
        XCTAssertThrowsError(try store.areas(sessionAppleID: "apple-b")) { error in
            XCTAssertEqual(error as? JournalError, .wrongAppleID)
        }
        XCTAssertEqual(try store.areas(sessionAppleID: "apple-a").map(\.name), ["arm"])
    }

    func testSignOutKeepsTheJournalForTheSameAppleID() throws {
        let store = try makeStore()
        _ = try store.beginSession(appleUserID: "apple-a", now: Date())
        _ = try store.createArea(name: "arm", now: Date())
        store.endSession()
        XCTAssertEqual(store.restoreSession(), .signedOut)
        XCTAssertEqual(try store.beginSession(appleUserID: "apple-a", now: Date()), .signedIn)
        XCTAssertEqual(try store.areas(sessionAppleID: "apple-a").map(\.name), ["arm"])
    }

    func testDeleteAreaAndAccountRemoveFiles() throws {
        let store = try makeStore()
        _ = try store.beginSession(appleUserID: "apple-a", now: Date())
        let area = try store.createArea(name: "arm", now: Date())
        _ = try store.saveCheckIn(
            areaID: area.id, sessionAppleID: "apple-a", jpeg: Data([3]),
            pixelWidth: 1, pixelHeight: 1, boxes: [], capturedAt: Date()
        )
        try store.deleteArea(id: area.id, sessionAppleID: "apple-a")
        XCTAssertTrue(try store.areas(sessionAppleID: "apple-a").isEmpty)
        try store.deleteAccount()
        XCTAssertEqual(store.restoreSession(), .signedOut)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(try store.beginSession(appleUserID: "apple-a", now: Date()), .signedIn)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests/JournalStoreTests
```

Expected: FAIL because `JournalStore` is not defined.

- [ ] **Step 3: Write the store**

Create `ios/MoleJournal/JournalStore.swift`:

```swift
import Foundation
import SwiftData

enum JournalError: Error, Equatable {
    case emptyName
    case saveFailed
    case wrongAppleID
    case notFound
}

enum SessionState: Equatable {
    case signedOut
    case signedIn
    case locked
}

@Model
final class ProfileRecord {
    var appleUserID: String
    var createdAt: Date

    init(appleUserID: String, createdAt: Date) {
        self.appleUserID = appleUserID
        self.createdAt = createdAt
    }
}

@Model
final class BodyAreaRecord {
    var id: UUID
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \CheckInRecord.area)
    var checkIns: [CheckInRecord] = []

    init(id: UUID, name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

@Model
final class CheckInRecord {
    var id: UUID
    var capturedAt: Date
    var imageFilename: String
    var pixelWidth: Int
    var pixelHeight: Int
    var area: BodyAreaRecord?
    @Relationship(deleteRule: .cascade, inverse: \MoleBoxRecord.checkIn)
    var boxes: [MoleBoxRecord] = []

    init(id: UUID, capturedAt: Date, imageFilename: String, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.capturedAt = capturedAt
        self.imageFilename = imageFilename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

@Model
final class MoleBoxRecord {
    var id: UUID
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var confidence: Double
    var label: String
    var hidden: Bool
    var checkIn: CheckInRecord?

    init(id: UUID, x: Double, y: Double, width: Double, height: Double, confidence: Double, label: String, hidden: Bool) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.confidence = confidence
        self.label = label
        self.hidden = hidden
    }
}

final class JournalStore {
    private let context: ModelContext
    private let imageDirectory: URL
    var failNextSave = false
    private var sessionAppleID: String?

    init(context: ModelContext, imageDirectory: URL) {
        self.context = context
        self.imageDirectory = imageDirectory
        ensureImageDirectory()
        sessionAppleID = try? String(contentsOf: sessionFile, encoding: .utf8)
    }

    func imageURL(filename: String) -> URL {
        imageDirectory.appendingPathComponent(filename)
    }

    func beginSession(appleUserID: String, now: Date) throws -> SessionState {
        ensureImageDirectory()
        if let profile = try fetchProfile() {
            guard profile.appleUserID == appleUserID else {
                endSession()
                return .locked
            }
            try writeSession(appleUserID)
            return .signedIn
        }
        context.insert(ProfileRecord(appleUserID: appleUserID, createdAt: now))
        try persist()
        try writeSession(appleUserID)
        return .signedIn
    }

    func endSession() {
        sessionAppleID = nil
        try? FileManager.default.removeItem(at: sessionFile)
    }

    func restoreSession() -> SessionState {
        guard let sessionAppleID, let profile = try? fetchProfile() else { return .signedOut }
        return profile.appleUserID == sessionAppleID ? .signedIn : .locked
    }

    func createArea(name: String, now: Date) throws -> BodyAreaRecord {
        guard let sessionAppleID else { throw JournalError.wrongAppleID }
        try requireOwner(sessionAppleID)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JournalError.emptyName }
        let area = BodyAreaRecord(id: UUID(), name: trimmed, createdAt: now)
        context.insert(area)
        try persist()
        return area
    }

    func areas(sessionAppleID: String) throws -> [BodyAreaRecord] {
        try requireOwner(sessionAppleID)
        let records = try context.fetch(FetchDescriptor<BodyAreaRecord>())
        return records.sorted { $0.createdAt > $1.createdAt }
    }

    func saveCheckIn(
        areaID: UUID,
        sessionAppleID: String,
        jpeg: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        boxes: [MoleBoxDraft],
        capturedAt: Date
    ) throws -> CheckInRecord {
        try requireOwner(sessionAppleID)
        guard let area = try fetchArea(areaID) else { throw JournalError.notFound }
        ensureImageDirectory()
        let filename = UUID().uuidString + ".jpg"
        let url = imageURL(filename: filename)
        try jpeg.write(to: url, options: .atomic)
        let checkIn = CheckInRecord(
            id: UUID(),
            capturedAt: capturedAt,
            imageFilename: filename,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
        checkIn.area = area
        context.insert(checkIn)
        for draft in boxes {
            let box = MoleBoxRecord(
                id: UUID(),
                x: draft.x,
                y: draft.y,
                width: draft.width,
                height: draft.height,
                confidence: draft.confidence,
                label: draft.label,
                hidden: draft.hidden
            )
            box.checkIn = checkIn
            context.insert(box)
        }
        do {
            if failNextSave {
                failNextSave = false
                throw JournalError.saveFailed
            }
            try context.save()
        } catch {
            context.rollback()
            try? FileManager.default.removeItem(at: url)
            throw JournalError.saveFailed
        }
        return checkIn
    }

    func checkIns(areaID: UUID, sessionAppleID: String) throws -> [CheckInRecord] {
        try requireOwner(sessionAppleID)
        guard let area = try fetchArea(areaID) else { throw JournalError.notFound }
        return area.checkIns.sorted { $0.capturedAt > $1.capturedAt }
    }

    func setBoxHidden(boxID: UUID, sessionAppleID: String, hidden: Bool) throws {
        try requireOwner(sessionAppleID)
        let records = try context.fetch(FetchDescriptor<MoleBoxRecord>())
        guard let box = records.first(where: { $0.id == boxID }) else { throw JournalError.notFound }
        box.hidden = hidden
        try persist()
    }

    func deleteCheckIn(id: UUID, sessionAppleID: String) throws {
        try requireOwner(sessionAppleID)
        let records = try context.fetch(FetchDescriptor<CheckInRecord>())
        guard let checkIn = records.first(where: { $0.id == id }) else { throw JournalError.notFound }
        try? FileManager.default.removeItem(at: imageURL(filename: checkIn.imageFilename))
        context.delete(checkIn)
        try persist()
    }

    func deleteArea(id: UUID, sessionAppleID: String) throws {
        try requireOwner(sessionAppleID)
        guard let area = try fetchArea(id) else { throw JournalError.notFound }
        for checkIn in area.checkIns {
            try? FileManager.default.removeItem(at: imageURL(filename: checkIn.imageFilename))
        }
        context.delete(area)
        try persist()
    }

    func deleteAccount() throws {
        for record in try context.fetch(FetchDescriptor<BodyAreaRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<ProfileRecord>()) {
            context.delete(record)
        }
        try persist()
        endSession()
        try? FileManager.default.removeItem(at: imageDirectory)
    }

    private var sessionFile: URL {
        imageDirectory.appendingPathComponent("session.txt")
    }

    private func ensureImageDirectory() {
        try? FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    }

    private func writeSession(_ appleUserID: String) throws {
        ensureImageDirectory()
        sessionAppleID = appleUserID
        try appleUserID.write(to: sessionFile, atomically: true, encoding: .utf8)
    }

    private func requireOwner(_ appleUserID: String) throws {
        guard let profile = try fetchProfile(), profile.appleUserID == appleUserID else {
            throw JournalError.wrongAppleID
        }
    }

    private func fetchProfile() throws -> ProfileRecord? {
        try context.fetch(FetchDescriptor<ProfileRecord>()).first
    }

    private func fetchArea(_ id: UUID) throws -> BodyAreaRecord? {
        try context.fetch(FetchDescriptor<BodyAreaRecord>()).first { $0.id == id }
    }

    private func persist() throws {
        try context.save()
    }
}
```

`failNextSave` stands in for a full disk. Set it after the profile and area already exist. `saveCheckIn` writes the JPEG, then throws before `context.save()`, rolls the unsaved check-in back, deletes that JPEG, and leaves the area with no new check-in. `beginSession` and `createArea` call `persist()` and are not affected. A mismatched Apple ID calls `endSession()` so the next launch stays signed out; the original records remain on disk for the first Apple ID. `deleteAccount()` removes the image directory, and the next `beginSession` creates it again.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests/JournalStoreTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/MoleJournal/JournalStore.swift ios/MoleJournalTests/JournalStoreTests.swift
git commit -m "feat: store body areas and check-ins on the phone"
```

---

### Task 4: Area list

**Files:**
- Create: `ios/MoleJournal/AreaListView.swift`
- Modify: `ios/MoleJournal/MoleJournalApp.swift`
- Test: `ios/MoleJournalTests/AreaListTests.swift`

**Interfaces:**
- Consumes: `JournalStore.createArea(name:now:)`, `JournalStore.areas(sessionAppleID:)`
- Produces: `struct AreaListView: View` and `func canSaveAreaName(_ name: String) -> Bool`

- [ ] **Step 1: Write the failing test**

Create `ios/MoleJournalTests/AreaListTests.swift`:

```swift
import XCTest
@testable import MoleJournal

final class AreaListTests: XCTestCase {
    func testBlankNameCannotBeSaved() {
        XCTAssertFalse(canSaveAreaName("   "))
        XCTAssertTrue(canSaveAreaName(" left shoulder "))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests/AreaListTests
```

Expected: FAIL because `canSaveAreaName` is not defined.

- [ ] **Step 3: Write the list**

Create `ios/MoleJournal/AreaListView.swift`:

```swift
import SwiftData
import SwiftUI

func canSaveAreaName(_ name: String) -> Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

struct AreaListView: View {
    @Bindable var store: JournalStoreModel
    var onSignOut: () -> Void = {}
    var onDeleteAccount: () -> Void = {}
    @State private var draftName = ""

    var body: some View {
        NavigationStack {
            List(store.areas) { area in
                NavigationLink(area.name) {
                    AreaDetailView(store: store, areaID: area.id)
                }
            }
            .overlay {
                if store.areas.isEmpty {
                    Text("Add a body area")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    TextField("Body area", text: $draftName)
                    Button("Add") {
                        store.addArea(name: draftName)
                        draftName = ""
                    }
                    .disabled(!canSaveAreaName(draftName))
                }
                .padding()
            }
            .navigationTitle("Body areas")
            .toolbar {
                Button("Sign out", action: onSignOut)
                Button("Delete account", action: onDeleteAccount)
            }
        }
    }
}
```

`JournalStoreModel` and `AreaDetailView` go in the same file. Put `import SwiftData` and `import SwiftUI` together at the top. `JournalStoreModel` is `@Observable` so `@Bindable` on the views is valid. One check-in has no comparison control; this task does not add a Compare button or any extra sentence.

```swift
@MainActor
@Observable
final class JournalStoreModel {
    private(set) var areas: [BodyAreaRecord] = []
    let sessionAppleID: String
    private let store: JournalStore

    init(store: JournalStore, sessionAppleID: String) {
        self.store = store
        self.sessionAppleID = sessionAppleID
        reload()
    }

    func reload() {
        areas = (try? store.areas(sessionAppleID: sessionAppleID)) ?? []
    }

    func addArea(name: String) {
        guard canSaveAreaName(name) else { return }
        _ = try? store.createArea(name: name, now: Date())
        reload()
    }

    func checkIns(areaID: UUID) -> [CheckInRecord] {
        (try? store.checkIns(areaID: areaID, sessionAppleID: sessionAppleID)) ?? []
    }
}

struct AreaDetailView: View {
    @Bindable var store: JournalStoreModel
    let areaID: UUID

    var body: some View {
        let items = store.checkIns(areaID: areaID)
        List(items) { item in
            Text(item.capturedAt.formatted(date: .abbreviated, time: .shortened))
        }
        .navigationTitle(store.areas.first { $0.id == areaID }?.name ?? "")
    }
}
```

`BodyAreaRecord` needs to be identifiable for `List`. Add this extension at the bottom of `JournalStore.swift`:

```swift
extension BodyAreaRecord: Identifiable {}
extension CheckInRecord: Identifiable {}
```

Replace `ios/MoleJournal/MoleJournalApp.swift` with a root that still shows the disclaimer until Task 8 wires Sign in with Apple. Keep the app building by showing `Text(Copy.signInDisclaimer)` when there is no session. The area list is constructed from tests and from Task 8.

```swift
import SwiftUI

@main
struct MoleJournalApp: App {
    var body: some Scene {
        WindowGroup {
            Text(Copy.signInDisclaimer)
                .multilineTextAlignment(.center)
                .padding()
        }
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/MoleJournal/AreaListView.swift ios/MoleJournal/JournalStore.swift ios/MoleJournal/MoleJournalApp.swift ios/MoleJournalTests/AreaListTests.swift
git commit -m "feat: list named body areas"
```

---

### Task 5: Capture flow without the live model

**Files:**
- Create: `ios/MoleJournal/CaptureFlowView.swift`
- Create: `ios/MoleJournal/ImageEncoding.swift`
- Test: `ios/MoleJournalTests/CaptureFlowTests.swift`

**Interfaces:**
- Consumes: `CaptureStep`, `advanceToCamera`, `initialCaptureStep`, `visibleBoxes`, `Copy.outlinesUnavailable`
- Produces:
  - `struct DetectionOutcome` with `boxes: [MoleBoxDraft]` and `outlinesUnavailable: Bool`
  - `protocol MoleDetecting { func detect(jpeg: Data) -> DetectionOutcome }`
  - `struct UprightImage` with `width: Int`, `height: Int`, `jpeg: Data`
  - `func jpegData(from image: UIImage) -> UprightImage?`
  - `func uprightSize(width: Int, height: Int, orientationIsRotated: Bool) -> (width: Int, height: Int)`
  - `func reviewMessage(_ outcome: DetectionOutcome) -> String?`
  - `struct CaptureFlowView` with `onSave`, `onCancel`, and `onCameraDenied`

- [ ] **Step 1: Write the failing test**

Create `ios/MoleJournalTests/CaptureFlowTests.swift`:

```swift
import XCTest
@testable import MoleJournal

final class CaptureFlowTests: XCTestCase {
    func testRotatedSizeSwapsDimensions() {
        let size = uprightSize(width: 1920, height: 1080, orientationIsRotated: true)
        XCTAssertEqual(size.width, 1080)
        XCTAssertEqual(size.height, 1920)
    }

    func testZeroBoxesHaveNoUnavailableMessage() {
        let outcome = DetectionOutcome(boxes: [], outlinesUnavailable: false)
        XCTAssertNil(reviewMessage(outcome))
    }

    func testFailedDetectionShowsUnavailable() {
        let outcome = DetectionOutcome(boxes: [], outlinesUnavailable: true)
        XCTAssertEqual(reviewMessage(outcome), Copy.outlinesUnavailable)
    }

    func testAdvanceFromInstructionReachesCameraWithGhost() {
        var step = initialCaptureStep(previousImageFilename: "last.jpg")
        step = advanceToCamera(step)
        XCTAssertEqual(step.phase, .camera)
        XCTAssertTrue(step.showsGhost)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests/CaptureFlowTests
```

Expected: FAIL because `uprightSize` is not defined.

- [ ] **Step 3: Write encoding, review state, and the capture view**

Create `ios/MoleJournal/ImageEncoding.swift`:

```swift
import Foundation
import UIKit

struct DetectionOutcome: Equatable {
    var boxes: [MoleBoxDraft]
    var outlinesUnavailable: Bool
}

protocol MoleDetecting {
    func detect(jpeg: Data) -> DetectionOutcome
}

struct UnavailableDetector: MoleDetecting {
    func detect(jpeg: Data) -> DetectionOutcome {
        DetectionOutcome(boxes: [], outlinesUnavailable: true)
    }
}

struct UprightImage {
    var width: Int
    var height: Int
    var jpeg: Data
}

func uprightSize(width: Int, height: Int, orientationIsRotated: Bool) -> (width: Int, height: Int) {
    orientationIsRotated ? (height, width) : (width, height)
}

func reviewMessage(_ outcome: DetectionOutcome) -> String? {
    outcome.outlinesUnavailable ? Copy.outlinesUnavailable : nil
}

func jpegData(from image: UIImage) -> UprightImage? {
    let rotated = image.imageOrientation != .up
    let size = uprightSize(
        width: Int(image.size.width * image.scale),
        height: Int(image.size.height * image.scale),
        orientationIsRotated: rotated
    )
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(
        size: CGSize(width: size.width, height: size.height),
        format: format
    )
    let rendered = renderer.image { _ in
        image.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    }
    guard let jpeg = rendered.jpegData(compressionQuality: 0.9) else { return nil }
    return UprightImage(width: size.width, height: size.height, jpeg: jpeg)
}
```

Create `ios/MoleJournal/CaptureFlowView.swift`:

```swift
import AVFoundation
import SwiftUI
import UIKit

struct CaptureFlowView: View {
    let previousImage: UIImage?
    let previousFilename: String?
    let detector: any MoleDetecting
    let onSave: (UprightImage, DetectionOutcome) -> Void
    let onCancel: () -> Void
    let onCameraDenied: () -> Void

    @State private var step: CaptureStep
    @State private var accepted: UprightImage?
    @State private var outcome = DetectionOutcome(boxes: [], outlinesUnavailable: false)
    @State private var drafts: [MoleBoxDraft] = []
    @StateObject private var cameraSession = CameraSession()

    init(
        previousImage: UIImage?,
        previousFilename: String?,
        detector: any MoleDetecting,
        onSave: @escaping (UprightImage, DetectionOutcome) -> Void,
        onCancel: @escaping () -> Void,
        onCameraDenied: @escaping () -> Void
    ) {
        self.previousImage = previousImage
        self.previousFilename = previousFilename
        self.detector = detector
        self.onSave = onSave
        self.onCancel = onCancel
        self.onCameraDenied = onCameraDenied
        _step = State(initialValue: initialCaptureStep(previousImageFilename: previousFilename))
    }

    var body: some View {
        VStack {
            switch step.phase {
            case .instruction:
                instruction
            case .camera:
                camera
            case .review:
                review
            }
        }
        .onDisappear {
            if step.phase != .review {
                accepted = nil
            }
        }
    }

    private var instruction: some View {
        VStack(spacing: 16) {
            if let previousImage, previousFilename != nil {
                Image(uiImage: previousImage)
                    .resizable()
                    .scaledToFit()
            }
            Text(step.instruction)
                .multilineTextAlignment(.center)
            Button("Continue") {
                step = advanceToCamera(step)
            }
            Button("Cancel", action: onCancel)
        }
        .padding()
    }

    private var camera: some View {
        ZStack {
            CameraPreviewView(session: cameraSession.session)
            if step.showsGhost, let previousImage {
                Image(uiImage: previousImage)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.4)
                    .allowsHitTesting(false)
            }
            VStack {
                Spacer()
                Button("Take photo") {
                    cameraSession.capture { image in
                        guard let upright = jpegData(from: image) else { return }
                        accepted = upright
                        outcome = detector.detect(jpeg: upright.jpeg)
                        drafts = outcome.boxes
                        step.phase = .review
                        cameraSession.stop()
                    }
                }
                Button("Cancel", action: onCancel)
            }
        }
        .onAppear {
            cameraSession.prepare { granted in
                if !granted { onCameraDenied() }
            }
        }
        .onDisappear { cameraSession.stop() }
    }

    private var review: some View {
        VStack {
            if let message = reviewMessage(outcome) {
                Text(message)
            }
            if let accepted, let image = UIImage(data: accepted.jpeg) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        BoxOverlay(boxes: visibleBoxes(drafts))
                    }
            }
            ForEach(drafts.indices, id: \.self) { index in
                Button(drafts[index].hidden ? "Unhide box" : "Hide box") {
                    drafts[index].hidden.toggle()
                }
            }
            Button("Retake") {
                accepted = nil
                drafts = []
                outcome = DetectionOutcome(boxes: [], outlinesUnavailable: false)
                step = advanceToCamera(initialCaptureStep(previousImageFilename: previousFilename))
            }
            Button("Save") {
                guard let accepted else { return }
                onSave(accepted, DetectionOutcome(boxes: drafts, outlinesUnavailable: outcome.outlinesUnavailable))
            }
            Button("Cancel", action: onCancel)
        }
    }
}

struct BoxOverlay: View {
    let boxes: [MoleBoxDraft]

    var body: some View {
        GeometryReader { proxy in
            ForEach(boxes.indices, id: \.self) { index in
                let box = boxes[index]
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(
                        width: proxy.size.width * box.width,
                        height: proxy.size.height * box.height
                    )
                    .position(
                        x: proxy.size.width * (box.x + box.width / 2),
                        y: proxy.size.height * (box.y + box.height / 2)
                    )
            }
        }
    }
}

final class CameraSession: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "MoleJournal.camera")
    private var onImage: ((UIImage) -> Void)?
    private var configured = false

    func prepare(onGranted: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start()
            onGranted(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.start() }
                    onGranted(granted)
                }
            }
        default:
            onGranted(false)
        }
    }

    func start() {
        queue.async {
            guard !self.configured else {
                if !self.session.isRunning { self.session.startRunning() }
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input),
                self.session.canAddOutput(self.output)
            else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.session.addOutput(self.output)
            self.session.commitConfiguration()
            self.configured = true
            self.session.startRunning()
        }
    }

    func capture(onImage: @escaping (UIImage) -> Void) {
        self.onImage = onImage
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { self.onImage?(image) }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
```

The live view is an `AVCaptureVideoPreviewLayer` the app owns. The previous photo is a sibling SwiftUI image at 40% opacity, aspect fit, and centered, so it stays visible over the camera. `UIImagePickerController` is not used, because its camera view covers that overlay. `fileDataRepresentation()` stays in memory. The app never calls a photo-library save API, so the JPEG is not copied to the Camera Roll. Nothing is written to the image directory until Save. Cancel, and leaving before Save, do not call `onSave`. A denied camera calls `onCameraDenied` and does not keep the preview up.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests/CaptureFlowTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/MoleJournal/ImageEncoding.swift ios/MoleJournal/CaptureFlowView.swift ios/MoleJournalTests/CaptureFlowTests.swift
git commit -m "feat: guide the next photo with the previous pose"
```

---

### Task 6: Map detector boxes onto the upright photo

**Files:**
- Create: `ios/MoleJournal/Detector.swift`
- Test: `ios/MoleJournalTests/DetectorMappingTests.swift`

**Interfaces:**
- Consumes: `MoleBoxDraft`, `DetectionOutcome`, `MoleDetecting`
- Produces:
  - `func normalizedRect(x1: Double, y1: Double, x2: Double, y2: Double, imageWidth: Int, imageHeight: Int) -> MoleBoxDraft`
  - `func topLeftRect(visionMinX: Double, visionMinY: Double, visionWidth: Double, visionHeight: Double) -> (x: Double, y: Double, width: Double, height: Double)`
  - `struct CoreMLMoleDetector: MoleDetecting`

- [ ] **Step 1: Write the failing test**

Create `ios/MoleJournalTests/DetectorMappingTests.swift`:

```swift
import XCTest
@testable import MoleJournal

final class DetectorMappingTests: XCTestCase {
    func testPixelBoxBecomesFractionsOfTheUprightImage() {
        let box = normalizedRect(x1: 10, y1: 20, x2: 50, y2: 40, imageWidth: 200, imageHeight: 100)
        XCTAssertEqual(box.x, 0.05)
        XCTAssertEqual(box.y, 0.20)
        XCTAssertEqual(box.width, 0.20)
        XCTAssertEqual(box.height, 0.20)
        XCTAssertEqual(box.label, "Mole")
        XCTAssertFalse(box.hidden)
    }

    func testVisionBottomLeftBoxBecomesTopLeft() {
        let rect = topLeftRect(visionMinX: 0.10, visionMinY: 0.20, visionWidth: 0.30, visionHeight: 0.40)
        XCTAssertEqual(rect.x, 0.10, accuracy: 0.0001)
        XCTAssertEqual(rect.y, 0.40, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 0.30, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 0.40, accuracy: 0.0001)
    }

    func testBoxesBelowTheThresholdAreDropped() {
        let kept = keepMoleObservations([
            (label: "Mole", confidence: 0.30, x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            (label: "Mole", confidence: 0.29, x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            (label: "images", confidence: 0.90, x: 0.1, y: 0.1, width: 0.2, height: 0.2),
        ])
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept[0].confidence, 0.30)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests/DetectorMappingTests
```

Expected: FAIL because `normalizedRect` is not defined.

- [ ] **Step 3: Write the detector**

Create `ios/MoleJournal/Detector.swift`:

```swift
import Foundation
import Vision
import CoreML

func normalizedRect(
    x1: Double,
    y1: Double,
    x2: Double,
    y2: Double,
    imageWidth: Int,
    imageHeight: Int
) -> MoleBoxDraft {
    MoleBoxDraft(
        x: x1 / Double(imageWidth),
        y: y1 / Double(imageHeight),
        width: (x2 - x1) / Double(imageWidth),
        height: (y2 - y1) / Double(imageHeight),
        confidence: 0.30,
        label: "Mole",
        hidden: false
    )
}

func topLeftRect(
    visionMinX: Double,
    visionMinY: Double,
    visionWidth: Double,
    visionHeight: Double
) -> (x: Double, y: Double, width: Double, height: Double) {
    (
        x: visionMinX,
        y: 1 - (visionMinY + visionHeight),
        width: visionWidth,
        height: visionHeight
    )
}

func keepMoleObservations(
    _ rows: [(label: String, confidence: Double, x: Double, y: Double, width: Double, height: Double)]
) -> [MoleBoxDraft] {
    rows.compactMap { row in
        guard row.label == "Mole", row.confidence >= 0.30 else { return nil }
        return MoleBoxDraft(
            x: row.x,
            y: row.y,
            width: row.width,
            height: row.height,
            confidence: row.confidence,
            label: "Mole",
            hidden: false
        )
    }
}

struct CoreMLMoleDetector: MoleDetecting {
    func detect(jpeg: Data) -> DetectionOutcome {
        guard
            let modelURL = Bundle.main.url(forResource: "MoleModel", withExtension: "mlmodelc"),
            let mlModel = try? MLModel(contentsOf: modelURL),
            let visionModel = try? VNCoreMLModel(for: mlModel)
        else {
            return DetectionOutcome(boxes: [], outlinesUnavailable: true)
        }
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFit
        let handler = VNImageRequestHandler(data: jpeg, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return DetectionOutcome(boxes: [], outlinesUnavailable: true)
        }
        guard let observations = request.results as? [VNRecognizedObjectObservation] else {
            return DetectionOutcome(boxes: [], outlinesUnavailable: true)
        }
        let rows = observations.map { observation in
            let rect = topLeftRect(
                visionMinX: observation.boundingBox.minX,
                visionMinY: observation.boundingBox.minY,
                visionWidth: observation.boundingBox.width,
                visionHeight: observation.boundingBox.height
            )
            let label = observation.labels.first?.identifier ?? ""
            return (
                label: label,
                confidence: Double(observation.confidence),
                x: rect.x,
                y: rect.y,
                width: rect.width,
                height: rect.height
            )
        }
        return DetectionOutcome(boxes: keepMoleObservations(rows), outlinesUnavailable: false)
    }
}
```

Copy the gated `yolo26s-mole-800px.mlpackage` into `ios/MoleJournal/MoleModel.mlpackage` only after `python3 model-check/compare_models.py` exits 0. From `ios`, run `xcodegen generate` so the local app target compiles that bundle to `MoleModel.mlmodelc`. Do not commit the `.mlpackage`, the skin photos, or an `xcodeproj` change that references the package. `*.mlpackage` is gitignored.

`normalizedRect` maps pixel boxes onto the upright image and stores the label `Mole`. It does not carry a measured confidence. `keepMoleObservations` does. `CoreMLMoleDetector` uses Vision's normalized boxes through `topLeftRect` and `keepMoleObservations`.

If the compiled model does not produce `VNRecognizedObjectObservation`, `detect` returns `outlinesUnavailable: true`. The photo still saves. The manual pass in Task 9 is what confirms boxes appear on a device.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests/DetectorMappingTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/MoleJournal/Detector.swift ios/MoleJournalTests/DetectorMappingTests.swift
git commit -m "feat: map on-device mole boxes onto the photo"
```

---

### Task 7: Comparison screen

**Files:**
- Create: `ios/MoleJournal/ComparisonView.swift`
- Modify: `ios/MoleJournal/AreaListView.swift` (add the comparison link on `AreaDetailView`)
- Test: `ios/MoleJournalTests/ComparisonTests.swift`

**Interfaces:**
- Consumes: `defaultComparison(newestFirst:)`, `visibleBoxes(_:)`, `CheckInRecord`
- Produces: `func choices(for side: ComparisonSide, selection: ComparisonSelection, newestFirst: [UUID]) -> [UUID]` and `struct ComparisonView`

- [ ] **Step 1: Write the failing test**

Create `ios/MoleJournalTests/ComparisonTests.swift`:

```swift
import XCTest
@testable import MoleJournal

final class ComparisonTests: XCTestCase {
    func testEachSideExcludesTheOtherCheckIn() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let selection = ComparisonSelection(leftID: a, rightID: b)
        XCTAssertEqual(choices(for: .left, selection: selection, newestFirst: [a, b, c]), [a, c])
        XCTAssertEqual(choices(for: .right, selection: selection, newestFirst: [a, b, c]), [b, c])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests/ComparisonTests
```

Expected: FAIL because `choices` is not defined.

- [ ] **Step 3: Write the comparison**

Create `ios/MoleJournal/ComparisonView.swift`:

```swift
import SwiftUI
import UIKit

enum ComparisonSide {
    case left
    case right
}

func choices(for side: ComparisonSide, selection: ComparisonSelection, newestFirst: [UUID]) -> [UUID] {
    let other = side == .left ? selection.rightID : selection.leftID
    return newestFirst.filter { $0 != other }
}

struct ComparisonView: View {
    let checkIns: [CheckInRecord]
    let image: (String) -> UIImage?
    @State private var selection: ComparisonSelection

    init(checkIns: [CheckInRecord], image: @escaping (String) -> UIImage?) {
        self.checkIns = checkIns
        self.image = image
        let ids = checkIns.map(\.id)
        guard let selection = defaultComparison(newestFirst: ids) else {
            preconditionFailure("ComparisonView requires two check-ins")
        }
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let ids = checkIns.map(\.id)
        VStack {
            HStack {
                photo(id: selection.leftID)
                photo(id: selection.rightID)
            }
            Picker("Left", selection: $selection.leftID) {
                ForEach(choices(for: .left, selection: selection, newestFirst: ids), id: \.self) { id in
                    Text(label(for: id)).tag(id)
                }
            }
            Picker("Right", selection: $selection.rightID) {
                ForEach(choices(for: .right, selection: selection, newestFirst: ids), id: \.self) { id in
                    Text(label(for: id)).tag(id)
                }
            }
        }
    }

    private func photo(id: UUID) -> some View {
        let checkIn = checkIns.first { $0.id == id }
        return VStack {
            if let checkIn, let uiImage = image(checkIn.imageFilename) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        BoxOverlay(boxes: visibleBoxes(checkIn.boxes.map(draft)))
                    }
            }
            if let checkIn {
                Text(checkIn.capturedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private func label(for id: UUID) -> String {
        checkIns.first { $0.id == id }?.capturedAt.formatted(date: .abbreviated, time: .shortened) ?? ""
    }

    private func draft(_ box: MoleBoxRecord) -> MoleBoxDraft {
        MoleBoxDraft(
            x: box.x, y: box.y, width: box.width, height: box.height,
            confidence: box.confidence, label: box.label, hidden: box.hidden
        )
    }
}
```

Add `import UIKit` under `import SwiftUI` in `ios/MoleJournal/AreaListView.swift`. Replace `AreaDetailView` with the list, the check-in detail, and a Compare link that exists only when the area has two check-ins. One check-in has no Compare button.

```swift
struct AreaDetailView: View {
    @Bindable var store: JournalStoreModel
    let areaID: UUID

    var body: some View {
        let items = store.checkIns(areaID: areaID)
        List(items) { item in
            NavigationLink {
                CheckInDetailView(store: store, areaID: areaID, checkInID: item.id)
            } label: {
                Text(item.capturedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .navigationTitle(store.areas.first { $0.id == areaID }?.name ?? "")
        .toolbar {
            if items.count >= 2 {
                NavigationLink("Compare") {
                    ComparisonView(checkIns: items) { filename in
                        UIImage(contentsOfFile: store.imageURL(filename: filename).path)
                    }
                }
            }
        }
    }
}

struct CheckInDetailView: View {
    @Bindable var store: JournalStoreModel
    let areaID: UUID
    let checkInID: UUID

    var body: some View {
        let checkIn = store.checkIns(areaID: areaID).first { $0.id == checkInID }
        VStack {
            if let checkIn, let uiImage = UIImage(contentsOfFile: store.imageURL(filename: checkIn.imageFilename).path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        BoxOverlay(boxes: visibleBoxes(checkIn.boxes.map(boxDraft)))
                    }
            }
            if let checkIn {
                ForEach(checkIn.boxes) { box in
                    Button(box.hidden ? "Unhide box" : "Hide box") {
                        store.setBoxHidden(boxID: box.id, hidden: !box.hidden)
                    }
                }
            }
        }
    }

    private func boxDraft(_ box: MoleBoxRecord) -> MoleBoxDraft {
        MoleBoxDraft(
            x: box.x, y: box.y, width: box.width, height: box.height,
            confidence: box.confidence, label: box.label, hidden: box.hidden
        )
    }
}
```

Add these methods inside `JournalStoreModel`, next to `checkIns(areaID:)`:

```swift
func setBoxHidden(boxID: UUID, hidden: Bool) {
    try? store.setBoxHidden(boxID: boxID, sessionAppleID: sessionAppleID, hidden: hidden)
    reload()
}

func imageURL(filename: String) -> URL {
    store.imageURL(filename: filename)
}
```

Add this extension at the bottom of `JournalStore.swift`:

```swift
extension MoleBoxRecord: Identifiable {}
```

- [ ] **Step 4: Run the tests**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/MoleJournal/ComparisonView.swift ios/MoleJournal/AreaListView.swift ios/MoleJournalTests/ComparisonTests.swift
git commit -m "feat: compare two photos of a body area"
```

---

### Task 8: Sign in, lock, sign out, and delete account

**Files:**
- Create: `ios/MoleJournal/SessionGateView.swift`
- Modify: `ios/MoleJournal/MoleJournalApp.swift`
- Modify: `ios/MoleJournal/AreaListView.swift` (check-in button, camera denial, capture sheet)
- Modify: `ios/MoleJournal/JournalStore.swift` (`signedInAppleID()`)
- Test: `ios/MoleJournalTests/SessionTests.swift`

**Interfaces:**
- Consumes: `JournalStore.beginSession(appleUserID:now:)`, `endSession()`, `deleteAccount()`, `restoreSession()`, `Copy.signInDisclaimer`, `Copy.lockedJournal`, `Copy.cameraRequired`
- Produces: `struct SessionGateView: View`. Canceling Sign in with Apple leaves the gate on screen. A `.locked` result shows `Copy.lockedJournal` and no area list.

- [ ] **Step 1: Write the failing test**

Create `ios/MoleJournalTests/SessionTests.swift`:

```swift
import XCTest
@testable import MoleJournal

final class SessionTests: XCTestCase {
    func testCancelStaysSignedOut() {
        XCTAssertEqual(sessionAfterAppleResult(.cancel, current: .signedOut), .signedOut)
    }

    func testMatchingIDSignsIn() {
        XCTAssertEqual(sessionAfterAppleResult(.matched, current: .signedOut), .signedIn)
    }

    func testDifferentIDLocks() {
        XCTAssertEqual(sessionAfterAppleResult(.differentID, current: .signedOut), .locked)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoleJournalTests/SessionTests
```

Expected: FAIL because `sessionAfterAppleResult` is not defined.

- [ ] **Step 3: Write the gate**

Add to `ios/MoleJournal/SessionGateView.swift`:

```swift
import AuthenticationServices
import SwiftUI

enum AppleSignInResult: Equatable {
    case cancel
    case matched
    case differentID
}

func sessionAfterAppleResult(_ result: AppleSignInResult, current: SessionState) -> SessionState {
    switch result {
    case .cancel:
        return current == .locked ? .locked : .signedOut
    case .matched:
        return .signedIn
    case .differentID:
        return .locked
    }
}

struct SessionGateView: View {
    let store: JournalStore
    @State private var session: SessionState

    init(store: JournalStore) {
        self.store = store
        _session = State(initialValue: store.restoreSession())
    }

    var body: some View {
        switch session {
        case .signedIn:
            signedIn
        case .locked:
            VStack(spacing: 16) {
                Text(Copy.lockedJournal)
                    .multilineTextAlignment(.center)
                signInButton
            }
            .padding()
        case .signedOut:
            VStack(spacing: 16) {
                Text(Copy.signInDisclaimer)
                    .multilineTextAlignment(.center)
                signInButton
            }
            .padding()
        }
    }

    private var signInButton: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = []
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                let next = (try? store.beginSession(appleUserID: credential.user, now: Date())) ?? .signedOut
                session = next
            case .failure:
                session = sessionAfterAppleResult(.cancel, current: session)
            }
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private var signedIn: some View {
        if let profileID = currentProfileID() {
            AreaListView(
                store: JournalStoreModel(store: store, sessionAppleID: profileID),
                onSignOut: {
                    store.endSession()
                    session = .signedOut
                },
                onDeleteAccount: {
                    try? store.deleteAccount()
                    session = .signedOut
                }
            )
        }
    }

    private func currentProfileID() -> String? {
        guard case .signedIn = session else { return nil }
        return store.signedInAppleID()
    }
}
```

Add this method to `JournalStore`:

```swift
func signedInAppleID() -> String? {
    guard case .signedIn = restoreSession() else { return nil }
    return sessionAppleID
}
```

Add this method inside `JournalStoreModel`:

```swift
func saveCheckIn(areaID: UUID, upright: UprightImage, outcome: DetectionOutcome) {
    _ = try? store.saveCheckIn(
        areaID: areaID,
        sessionAppleID: sessionAppleID,
        jpeg: upright.jpeg,
        pixelWidth: upright.width,
        pixelHeight: upright.height,
        boxes: outcome.boxes,
        capturedAt: Date()
    )
    reload()
}
```

Add `import AVFoundation` under the imports in `ios/MoleJournal/AreaListView.swift`. Replace `AreaDetailView` with this version. A denied or restricted camera shows `Copy.cameraRequired` and a Settings link, and does not present the capture sheet. The latest check-in, when one exists, is the previous photo. The first check-in passes nil for both the image and the filename. `CoreMLMoleDetector` is the detector. Zero boxes and `outlinesUnavailable` still call `saveCheckIn`.

```swift
struct AreaDetailView: View {
    @Bindable var store: JournalStoreModel
    let areaID: UUID
    @State private var showCapture = false
    @State private var cameraDenied = false

    var body: some View {
        let items = store.checkIns(areaID: areaID)
        List(items) { item in
            NavigationLink {
                CheckInDetailView(store: store, areaID: areaID, checkInID: item.id)
            } label: {
                Text(item.capturedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .navigationTitle(store.areas.first { $0.id == areaID }?.name ?? "")
        .toolbar {
            Button("New check-in") {
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                if status == .denied || status == .restricted {
                    cameraDenied = true
                } else {
                    showCapture = true
                }
            }
            if items.count >= 2 {
                NavigationLink("Compare") {
                    ComparisonView(checkIns: items) { filename in
                        UIImage(contentsOfFile: store.imageURL(filename: filename).path)
                    }
                }
            }
        }
        .alert(Copy.cameraRequired, isPresented: $cameraDenied) {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Close", role: .cancel) {}
        }
        .sheet(isPresented: $showCapture) {
            let latest = items.first
            CaptureFlowView(
                previousImage: latest.flatMap {
                    UIImage(contentsOfFile: store.imageURL(filename: $0.imageFilename).path)
                },
                previousFilename: latest?.imageFilename,
                detector: CoreMLMoleDetector(),
                onSave: { upright, outcome in
                    store.saveCheckIn(areaID: areaID, upright: upright, outcome: outcome)
                    showCapture = false
                },
                onCancel: { showCapture = false },
                onCameraDenied: {
                    showCapture = false
                    cameraDenied = true
                }
            )
        }
    }
}
```

Replace `MoleJournalApp.swift`:

```swift
import SwiftData
import SwiftUI

@main
struct MoleJournalApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([
            ProfileRecord.self,
            BodyAreaRecord.self,
            CheckInRecord.self,
            MoleBoxRecord.self,
        ])
        container = try! ModelContainer(for: schema)
    }

    var body: some Scene {
        WindowGroup {
            SessionGateView(
                store: JournalStore(
                    context: ModelContext(container),
                    imageDirectory: journalDirectory()
                )
            )
        }
    }
}

func journalDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("MoleJournal", isDirectory: true)
}
```

- [ ] **Step 4: Run the full unit suite**

```bash
cd ios
xcodebuild test -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/MoleJournal/SessionGateView.swift ios/MoleJournal/MoleJournalApp.swift ios/MoleJournal/AreaListView.swift ios/MoleJournal/JournalStore.swift ios/MoleJournalTests/SessionTests.swift
git commit -m "feat: unlock the journal with Sign in with Apple"
```

---

### Task 9: Manual App Store pass

**Files:**
- Modify: none

**Interfaces:**
- Consumes: the app built by Tasks 1–8 and `MoleModel.mlpackage` copied into `ios/MoleJournal/` after the model gate exits 0

- [ ] **Step 1: Install on a device**

Run from `ios`:

```bash
xcodebuild -project MoleJournal.xcodeproj -scheme MoleJournal -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

Install that build on an iPhone with Xcode. The simulator cannot complete Sign in with Apple or the camera steps below.

- [ ] **Step 2: Walk the journal**

Expected results, in order:

1. The first screen shows `A personal photo log of skin areas. It does not diagnose.`
2. Canceling Sign in with Apple leaves that screen in place.
3. Signing in opens an empty list that says `Add a body area`.
4. Adding `left shoulder` shows that area. Adding another `left shoulder` shows a second row.
5. The first check-in shows `Fill the frame with the area, hold a steady distance, and use the same lighting next time.` The camera has no faded photo.
6. Saving that photo, even with zero boxes, adds one check-in. There is no Compare button.
7. The second check-in shows the first photo and `Match this pose.` The camera shows that photo at 40% opacity, aspect fit, centered.
8. Compare opens the two full photos with dates. Hidden boxes are absent. The two sides cannot be the same check-in.
9. Hiding a box on the check-in and returning to Compare leaves that box off the photo. Unhide brings it back.
10. Denying the camera and starting a check-in shows `The camera is required to photograph a body area.` The area's check-ins are unchanged.
11. Sign out returns to the disclaimer. Signing in with the same Apple ID shows the photos. Signing in with a different Apple ID shows `This phone's journal belongs to a different Apple ID.` and no photos.
12. Delete account removes the photos. Force-quit and relaunch shows the disclaimer and an empty journal after signing in again.
13. The Photos app has no new image from this walk.

- [ ] **Step 3: Commit only if a defect fix was required**

If the walk matches Step 2, do not make an empty commit. If a fix was required, commit that fix with the test that now covers it.
