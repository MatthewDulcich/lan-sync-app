import Foundation

enum OpKind: String, Codable {
  case claim
  case unclaim
  case verifySet
  case challengeSet
  case illegibleSet
  case editFields
  case attachImage
  case createUnit
  case deleteUnit
}

struct Op: Codable, Identifiable {
  var epoch: UInt64
  var seq: UInt64?
  var opId: UUID
  var authorDevice: String
  var time: Date
  var kind: OpKind
  var recordID: UUID
  var fields: [String: FieldValue]? = nil
  var boolValue: Bool? = nil
  var blobHash: String? = nil
  var claimOwner: String? = nil

  var id: UUID { opId }
}