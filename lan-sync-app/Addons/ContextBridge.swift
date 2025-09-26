import SwiftUI
import SwiftData

struct ContextBridge: View {
    @Environment(\.modelContext) private var ctx
    var body: some View {
        Color.clear.onAppear {
            Replicator.shared.injectContext(ctx)
        }
    }
}
