//
//  IceMeltBarLocation.swift
//  IceMelt
//

import SwiftUI

/// Locations where the IceMelt Bar can appear.
enum IceMeltBarLocation: Int, CaseIterable, Identifiable {
    /// The IceMelt Bar will appear in different locations based on context.
    case dynamic = 0

    /// The IceMelt Bar will appear centered below the mouse pointer.
    case mousePointer = 1

    /// The IceMelt Bar will appear centered below the IceMelt icon.
    case iceMeltIcon = 2

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .dynamic: "Dynamic"
        case .mousePointer: "Mouse pointer"
        case .iceMeltIcon: "IceMelt icon"
        }
    }
}
