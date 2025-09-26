import SwiftUI

struct ModeSelectorView: View {
    @EnvironmentObject var session: SessionManager

    var body: some View {
        HStack(spacing: 12) {
            Button {
                session.startHosting()
            } label: {
                Label("Become Host", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.borderedProminent)

            Button {
                session.joinViaQR()
            } label: {
                Label("Join via QR", systemImage: "qrcode.viewfinder")
            }
            .buttonStyle(.bordered)

            if !session.isHost {
                Button {
                    session.requestHostship()
                } label: {
                    Label("Request Hostship", systemImage: "arrow.2.circlepath")
                }
            }
        }
    }
}