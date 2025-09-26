#if false
// Disabled: This stub collided with the real implementation in Replicator.swift and caused
// "Ambiguous use of 'injectContext'" at call sites. Keep only the real method.
import Foundation
import SwiftData

extension Replicator {
    func injectContext(_ ctx: ModelContext) {
        _ = ctx // placeholder (disabled)
    }
}
#endif
