import Foundation
import SwiftData

extension Replicator {
    func injectContext(_ ctx: ModelContext) {
        _ = ctx // hold a weak/global reference if you restructure; demo keeps existing apply() signature
    }
}
