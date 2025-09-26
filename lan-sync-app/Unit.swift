import Foundation
import SwiftData

@Model
public final class Unit {
    public var id: UUID
    public var answer: String?
    public var eventDate: Date?
    public var eventName: String?
    public var blobHash: String?    // repurposed from imageURL
    public var isVerified: Bool
    public var isProcessing: Bool
    public var isChallenged: Bool
    public var isIllegible: Bool
    public var questionNumber: Int16
    public var teamClub: String?
    public var teamCode: String?
    public var teamName: String?
    public var timeStamp: Date
    public var lastEditor: String?

    public init(id: UUID,
                answer: String?,
                eventDate: Date?,
                eventName: String?,
                blobHash: String?,
                isVerified: Bool,
                isProcessing: Bool,
                isChallenged: Bool,
                isIllegible: Bool,
                questionNumber: Int16,
                teamClub: String?,
                teamCode: String?,
                teamName: String?,
                timeStamp: Date,
                lastEditor: String?) {
        self.id = id
        self.answer = answer
        self.eventDate = eventDate
        self.eventName = eventName
        self.blobHash = blobHash
        self.isVerified = isVerified
        self.isProcessing = isProcessing
        self.isChallenged = isChallenged
        self.isIllegible = isIllegible
        self.questionNumber = questionNumber
        self.teamClub = teamClub
        self.teamCode = teamCode
        self.teamName = teamName
        self.timeStamp = timeStamp
        self.lastEditor = lastEditor
    }
}