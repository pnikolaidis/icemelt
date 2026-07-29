//
//  MenuBarItemService.swift
//  Shared
//

import CoreGraphics
import Foundation

enum MenuBarItemService {
    static let name = "com.pnikolaidis.iceMeltmelt.MenuBarItemService"
}

extension MenuBarItemService {
    enum Request: Codable {
        case start
        case sourcePID(WindowInfo)
        case sourcePIDs([WindowInfo])
    }

    enum Response: Codable {
        case start
        case sourcePID(pid_t?)
        case sourcePIDs([CGWindowID: pid_t])
    }
}
