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
