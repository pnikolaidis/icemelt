//
//  IceMeltApp.swift
//  IceMelt
//

import SwiftUI

@main
struct IceMeltApp: App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate

    var body: some Scene {
        SettingsWindow(appState: appDelegate.appState)
        PermissionsWindow(appState: appDelegate.appState)
    }
}
