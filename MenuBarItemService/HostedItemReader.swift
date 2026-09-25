//
//  HostedItemReader.swift
//  MenuBarItemService
//

import AXSwift
import Cocoa
import os

/// Reads the menu bar items hosted by `MenuBarAgent` (macOS 27 and later)
/// from the agent's accessibility tree.
///
/// The tree is one `AXWindow` per display, each holding one child per
/// item slot. A slot's child is an element from the process that created
/// the item, so its pid is the item's source process, which the window
/// server no longer tells us. Only the agent's own elements are ever
/// messaged: a third-party item's element is read for its pid alone,
/// which needs no round trip to that process, so an unresponsive app
/// cannot stall the read (compare ``SourcePIDCache``).
enum HostedItemReader {
    /// The messaging timeout for calls into `MenuBarAgent`. The agent is a
    /// system service and answers quickly; the timeout only bounds the
    /// damage if it doesn't.
    private static let messagingTimeout: Float = 1

    /// Returns the hosted items across all displays, or an empty array
    /// when the agent isn't running or its tree can't be read.
    static func read() -> [HostedMenuBarItem] {
        guard AXHelpers.isProcessTrusted() else {
            return []
        }
        guard
            let agentApp = NSRunningApplication
                .runningApplications(withBundleIdentifier: HostedMenuBarItem.agentBundleIdentifier)
                .first,
            let agent = AXHelpers.application(for: agentApp)
        else {
            Logger.default.warning("MenuBarAgent is not available for reading hosted items")
            return []
        }
        AXHelpers.setMessagingTimeout(messagingTimeout, for: agent)

        let agentPID = agentApp.processIdentifier
        var items = [HostedMenuBarItem]()

        for (hostIndex, window) in AXHelpers.windows(for: agent).enumerated() {
            guard let hostFrame = AXHelpers.frame(for: window) else {
                continue
            }
            for slot in AXHelpers.children(for: window) {
                guard
                    let frame = AXHelpers.frame(for: slot),
                    frame.width > 0
                else {
                    continue
                }
                // The overflow chevron has no process behind it, and no
                // content element. It is kept, with a source pid of 0, so
                // the app knows where it is.
                let content = AXHelpers.children(for: slot).first
                let sourcePID = content.flatMap(AXHelpers.pid(for:)) ?? 0
                let isSystemExtra = sourcePID == agentPID
                var identifier: String?
                if isSystemExtra, let content {
                    // The hosting view wraps a menu extra element that carries
                    // a stable identifier ("com.apple.menuextra.clock").
                    let extra = AXHelpers.children(for: content).first ?? content
                    identifier = AXHelpers.identifier(for: extra)
                }
                items.append(
                    HostedMenuBarItem(
                        frame: frame,
                        hostFrame: hostFrame,
                        hostIndex: hostIndex,
                        sourcePID: sourcePID,
                        isSystemExtra: isSystemExtra,
                        identifier: identifier
                    )
                )
            }
        }

        return items
    }
}
