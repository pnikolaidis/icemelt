//
//  HostedMenuBarItem.swift
//  Shared
//

import CoreGraphics
import Foundation

/// A menu bar item as hosted by `MenuBarAgent`.
///
/// As of macOS 27, status items are no longer individual windows. The
/// whole menu bar of each display is a single window owned by the
/// `MenuBarAgent` process, and the items are scenes hosted inside it.
/// The only public view of the items is the agent's accessibility tree:
/// one element per display window, each with one child element per item
/// slot, whose own child is an element vended by the process that created
/// the item (or by the agent itself, for the system menu extras).
struct HostedMenuBarItem: Codable, Hashable {
    /// The frame of the item, in screen coordinates.
    let frame: CGRect

    /// The frame of the menu bar window hosting the item, in screen
    /// coordinates. There is one hosting window per display.
    let hostFrame: CGRect

    /// The identifier of the process that created the item.
    ///
    /// For the system menu extras this is the `MenuBarAgent` process. The
    /// overflow chevron has no process behind it and reports 0.
    let sourcePID: pid_t

    /// A Boolean value that indicates whether the item is the chevron
    /// that opens the system overflow.
    var isOverflowChevron: Bool {
        sourcePID == 0
    }

    /// A Boolean value that indicates whether the item is a system menu
    /// extra hosted by `MenuBarAgent` itself.
    let isSystemExtra: Bool

    /// The accessibility identifier of a system menu extra, such as
    /// `com.apple.menuextra.clock`. Always `nil` for other items, whose
    /// accessibility attributes are deliberately never read.
    let identifier: String?
}

extension HostedMenuBarItem {
    /// The bundle identifier of the `MenuBarAgent` process.
    static let agentBundleIdentifier = "com.apple.MenuBarAgent"
}
