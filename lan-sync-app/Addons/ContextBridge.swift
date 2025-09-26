import SwiftUI
import SwiftData

struct ContextBridge: View {
    @Environment(\.modelContext) private var ctx
    @State private var hasInjected = false

    var body: some View {
        EmptyView()
            .onAppear {
                // Inject the SwiftData model context once when this view appears.
                if !hasInjected {
                    hasInjected = true
                    Replicator.shared.injectContext(ctx)
                }
            }
    }
}
