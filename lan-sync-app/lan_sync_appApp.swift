//
//  lan_sync_appApp.swift
//  lan-sync-app
//
//  Created by Matthew Dulcich on 9/25/25.
//

import SwiftUI
import Combine
import SwiftData

@main
struct LANSyncAppApp: App {
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var diagnostics = DiagnosticsModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .environmentObject(diagnostics)
        }
        .modelContainer(for: Unit.self)
    }
}

