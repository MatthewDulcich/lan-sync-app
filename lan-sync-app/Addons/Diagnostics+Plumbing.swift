import Foundation

extension DiagnosticsModel {
    func setPeers(_ list: [String]) {
        DispatchQueue.main.async { self.peers = list }
    }
}
