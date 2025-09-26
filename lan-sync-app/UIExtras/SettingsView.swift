import SwiftUI

struct SettingsView: View {
    @AppStorage("PersonName") private var personName: String = ""
    @AppStorage("DefaultLeaseSeconds") private var defaultLease: Double = 300
    @EnvironmentObject var session: SessionManager

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Your name", text: $personName)
                LabeledContent("Device", value: Host.currentName)
                LabeledContent("Display As", value: "\(personName.isEmpty ? "User" : personName)@\(Host.currentName)")
            }
            Section("Claim / Lease") {
                Stepper(value: $defaultLease, in: 60...3600, step: 30) {
                    Text("Default lease: \(Int(defaultLease))s")
                }
                Text("Host enforces first-writer-wins; leases can be expired manually or by timeout.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Session") {
                if session.isHost {
                    NavigationLink("Show Host QR") { HostQRView() }
                } else {
                    NavigationLink("Join via QR") { JoinView() }
                }
            }
        }
        .navigationTitle("Settings")
        .onChange(of: personName) { _ in
            session.personName = personName.isEmpty ? "User" : personName
        }
        .onAppear {
            if personName.isEmpty { personName = session.personName }
        }
    }
}