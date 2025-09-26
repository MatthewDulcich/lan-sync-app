import SwiftUI

struct JoinView: View {
    @EnvironmentObject var session: SessionManager
    @State private var pasted: String = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            if QRScannerView.isSupported {
                QRScannerView { code in
                    if let info = QRJoinCodec.decode(code) {
                        session.join(with: info)
                    } else {
                        error = "Invalid QR payload"
                    }
                }
                .frame(height: 320)
            } else {
                Text("Camera scanning not available; paste the code below.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $pasted).frame(height: 140).border(.secondary)
                Button("Join from pasted code") {
                    if let info = QRJoinCodec.decode(pasted) {
                        session.join(with: info)
                    } else {
                        error = "Invalid code"
                    }
                }
            }
            if let error = error { Text(error).foregroundStyle(.red) }
            Spacer()
        }
        .padding()
        .navigationTitle("Join via QR")
    }
}