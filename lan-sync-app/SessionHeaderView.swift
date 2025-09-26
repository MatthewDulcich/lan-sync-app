import SwiftUI

struct SessionHeaderView: View {
    @EnvironmentObject var session: SessionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session: \(session.sessionID ?? "—")")
            Text("Epoch: \(session.epoch) • Host: \(session.isHost ? "This device" : (session.currentHostID ?? "unknown"))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}