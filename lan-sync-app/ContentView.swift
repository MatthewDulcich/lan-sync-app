//
//  ContentView.swift
//  lan-sync-app
//
//  Created by Matthew Dulcich on 9/25/25.
//

import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var diag: DiagnosticsModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                SessionHeaderView()
                Divider()
                ModeSelectorView()
                Divider()
                ContentListView()
                Divider()
                NavigationLink("Diagnostics") { DiagnosticsView() }
                NavigationLink("Settings") { SettingsView() }
            }
            .overlay(ContextBridge().hidden())
            .padding()
            .navigationTitle("LAN Sync")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionManager())
        .environmentObject(DiagnosticsModel.shared)
}
