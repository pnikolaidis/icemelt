//
//  MenuBarItemImageCache.swift
//  IceMelt
//

import Cocoa
import Combine
import OSLog

/// Cache for menu bar item images.
final class MenuBarItemImageCache: ObservableObject {
    /// A representation of a captured menu bar item image.
    struct CapturedImage: Hashable {
        /// The base image.
        let cgImage: CGImage

        /// The scale factor of the image at the time of capture.
        let scale: CGFloat

        /// The image's size, applying ``scale``.
        var scaledSize: CGSize {
            CGSize(
                width: CGFloat(cgImage.width) / scale,
                height: CGFloat(cgImage.height) / scale
            )
        }

        /// The base image, converted to an `NSImage` and applying ``scale``.
        var nsImage: NSImage {
            NSImage(cgImage: cgImage, size: scaledSize)
        }
    }

    /// The result of an image capture operation.
    private struct CaptureResult {
        /// The successfully captured images.
        var images = [MenuBarItemTag: CapturedImage]()

        /// The menu bar items excluded from the capture.
        var excluded = [MenuBarItem]()
    }

    /// The cached item images, keyed by their corresponding tags.
    @Published private(set) var images = [MenuBarItemTag: CapturedImage]()

    /// Images of hosted items (macOS 27), cut from `MenuBarAgent`'s bar
    /// whenever the items are laid out, with the time of capture. Kept
    /// across updates: an item stacked in the collapsed overflow can't be
    /// captured, so its last capture stands in until it is laid out again.
    @MainActor private var hostedImages = [MenuBarItemTag: (image: CapturedImage, date: Date)]()

    /// Whether a capture of hosted items is in progress.
    @MainActor private var isCapturingHostedItems = false

    /// Logger for the menu bar item image cache.
    private let logger = Logger(category: "MenuBarItemImageCache")

    /// Queue to run cache operations.
    private let queue = DispatchQueue(label: "MenuBarItemImageCache", qos: .background)

    /// Image capture options.
    private let captureOption: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    // MARK: Setup

    /// Sets up the cache.
    @MainActor
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
    }

    /// Configures the internal observers for the cache.
    @MainActor
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            Publishers.Merge3(
                // Update every 3 seconds at minimum.
                Timer.publish(every: 3, on: .main, in: .default).autoconnect().replace(with: ()),

                // Update when the active space or screen parameters change.
                Publishers.Merge(
                    NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
                    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                )
                .replace(with: ()),

                // Update when the average menu bar color or cached items change.
                Publishers.Merge(
                    appState.menuBarManager.$averageColorInfo.removeDuplicates().replace(with: ()),
                    appState.itemManager.$itemCache.removeDuplicates().replace(with: ())
                )
            )
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: false)
            .sink { [weak self] in
                guard let self else {
                    return
                }
                Task {
                    await self.updateCache()
                }
            }
            .store(in: &c)

            if #available(macOS 27.0, *) {
                // Hosted items can only be captured while laid out, which for
                // hidden ones is brief, so watch for it whatever is presented.
                Publishers.Merge(
                    Timer.publish(every: 3, on: .main, in: .default).autoconnect().replace(with: ()),
                    appState.itemManager.$itemCache.removeDuplicates().replace(with: ())
                )
                .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] in
                    guard let self else {
                        return
                    }
                    Task {
                        await self.captureHostedItems(appState: appState)
                    }
                }
                .store(in: &c)
            }
        }

        cancellables = c
    }

    // MARK: Capturing Images

    /// Captures a composite image of the given items, then crops out an image
    /// for each item and returns the result.
    ///
    /// The scale is derived from the capture itself rather than taken from a
    /// screen, since ``captureOption`` includes `.bestResolution` and returns
    /// the image at the capturing display's pixel density.
    private nonisolated func compositeCapture(_ items: [MenuBarItem]) -> CaptureResult {
        var result = CaptureResult()

        var windowIDs = [CGWindowID]()
        var storage = [CGWindowID: (MenuBarItem, CGRect)]()
        var boundsUnion = CGRect.null

        for item in items {
            let windowID = item.windowID

            // Don't use `item.bounds`, it could be out of date.
            guard let bounds = Bridging.getWindowBounds(for: windowID) else {
                result.excluded.append(item)
                continue
            }

            windowIDs.append(windowID)
            storage[windowID] = (item, bounds)
            boundsUnion = boundsUnion.union(bounds)
        }

        guard
            let compositeImage = ScreenCapture.captureWindows(with: windowIDs, option: captureOption),
            boundsUnion.width >= 1,
            boundsUnion.height >= 1,
            !compositeImage.isTransparent()
        else {
            result.excluded = items // Exclude all items.
            return result
        }

        let scale = CGFloat(compositeImage.width) / boundsUnion.width

        // Safety check. A capture that corresponds to `boundsUnion` is scaled
        // by the same factor in both dimensions; the tolerance absorbs the
        // rounding of the image's integral pixel dimensions.
        guard abs(scale - CGFloat(compositeImage.height) / boundsUnion.height) < 0.05 else {
            result.excluded = items // Exclude all items.
            return result
        }

        // Crop out each item from the composite.
        for windowID in windowIDs {
            guard let (item, bounds) = storage[windowID] else {
                continue
            }

            let cropRect = CGRect(
                x: (bounds.origin.x - boundsUnion.origin.x) * scale,
                y: (bounds.origin.y - boundsUnion.origin.y) * scale,
                width: bounds.width * scale,
                height: bounds.height * scale
            )

            guard
                let image = compositeImage.cropping(to: cropRect),
                !image.isTransparent()
            else {
                result.excluded.append(item)
                continue
            }

            result.images[item.tag] = CapturedImage(cgImage: image, scale: scale)
        }

        return result
    }

    /// Captures an image of each of the given items individually, then
    /// returns the result.
    ///
    /// - Parameters:
    ///   - items: The items to capture.
    ///   - scale: The scale to apply to an item whose current bounds can't be
    ///     read. Where they can, the scale is derived from the capture, for
    ///     the reason given in ``compositeCapture(_:)``.
    private nonisolated func individualCapture(_ items: [MenuBarItem], scale: CGFloat) -> CaptureResult {
        var result = CaptureResult()

        for item in items {
            guard
                let image = ScreenCapture.captureWindow(with: item.windowID, option: captureOption),
                !image.isTransparent()
            else {
                result.excluded.append(item)
                continue
            }

            let capturedScale: CGFloat = if
                let bounds = Bridging.getWindowBounds(for: item.windowID),
                bounds.width >= 1
            {
                CGFloat(image.width) / bounds.width
            } else {
                scale
            }

            result.images[item.tag] = CapturedImage(cgImage: image, scale: capturedScale)
        }

        return result
    }

    /// Captures the images of the given menu bar items and returns the result.
    private nonisolated func captureImages(of items: [MenuBarItem], scale: CGFloat, appState: AppState) async -> CaptureResult {
        // Hosted items (macOS 27) have no windows to capture. Exclude them all
        // so they get the app-icon fallback, without a round of failed captures.
        // Use the captures cut from MenuBarAgent's bar, and the app-icon
        // fallback for items not yet laid out since launch.
        if items.allSatisfy(\.isHosted) {
            let stored = await MainActor.run { hostedImages }
            var result = CaptureResult()
            for item in items {
                if let image = stored[item.tag]?.image {
                    result.images[item.tag] = image
                } else {
                    result.excluded.append(item)
                }
            }
            return result
        }

        // Use individual capture after a move operation, since composite capture
        // doesn't account for overlapping items.
        if await appState.itemManager.lastMoveOperationOccurred(within: .seconds(2)) {
            logger.debug("Capturing individually due to recent item movement")
            return individualCapture(items, scale: scale)
        }

        let compositeResult = compositeCapture(items)

        if compositeResult.excluded.isEmpty {
            return compositeResult // All items captured successfully.
        }

        logger.notice(
            """
            Some items were excluded from composite capture. Attempting to capture \
            excluded items individually: \(compositeResult.excluded, privacy: .public)
            """
        )

        var individualResult = individualCapture(compositeResult.excluded, scale: scale)

        // Merge the successfully captured images from each result. Keep excluded
        // items as part of the result, so they can be logged elsewhere.
        individualResult.images.merge(compositeResult.images) { (_, new) in new }

        return individualResult
    }

    /// Renders a stand-in image for an item whose window can't be captured,
    /// drawing the source app's icon centered in a canvas of the item's size.
    ///
    /// Used when Screen Recording permission is missing, or when capture
    /// fails for an individual item (both common on macOS 26).
    private nonisolated func fallbackImage(for item: MenuBarItem, scale: CGFloat) -> CapturedImage? {
        guard let icon = hostedExtraSymbol(for: item) ?? (item.sourceApplication ?? item.owningApplication)?.icon else {
            return nil
        }

        var itemSize = item.bounds.size
        if itemSize.width < 1 || itemSize.height < 1 {
            itemSize = CGSize(width: 30, height: 24)
        }

        let width = Int(itemSize.width * scale)
        let height = Int(itemSize.height * scale)
        guard
            width > 0, height > 0,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        let iconSide = min(itemSize.height * 0.65, itemSize.width) * scale
        var proposedRect = CGRect(x: 0, y: 0, width: iconSide, height: iconSide)
        guard let iconImage = icon.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        context.draw(
            iconImage,
            in: CGRect(
                x: (CGFloat(width) - iconSide) / 2,
                y: (CGFloat(height) - iconSide) / 2,
                width: iconSide,
                height: iconSide
            )
        )

        guard let image = context.makeImage() else {
            return nil
        }
        return CapturedImage(cgImage: image, scale: scale)
    }

    /// Returns a symbol standing in for a system menu extra hosted by
    /// `MenuBarAgent` (macOS 27), whose "source app" has no icon of its own.
    private nonisolated func hostedExtraSymbol(for item: MenuBarItem) -> NSImage? {
        guard item.tag.namespace == .menuBarAgent else {
            return nil
        }
        let name = switch item.tag.title.replacing(/^com\.apple\.menuextra\./, with: "") {
        case "wifi": "wifi"
        case "battery": "battery.75percent"
        case "sound": "speaker.wave.2.fill"
        case "focusmode": "moon.fill"
        case "clock": "clock"
        case "controlcenter": "switch.2"
        case "bluetooth": "bluetooth" // Not an SF Symbol; falls through to the generic one below.
        default: "menubar.rectangle"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: item.displayName)
            ?? NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: item.displayName)
        return image?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
    }

    /// Captures the images of the menu bar items in the given section and returns
    /// a dictionary containing the images, keyed by their menu bar item tags.
    ///
    /// Items that can't be captured (individually, or wholesale when `canCapture`
    /// is `false`) fall back to a rendering of their source app's icon.
    private func captureImages(for section: MenuBarSection.Name, scale: CGFloat, appState: AppState, canCapture: Bool) async -> [MenuBarItemTag: CapturedImage] {
        let items = await appState.itemManager.itemCache.managedItems(for: section)

        var images = [MenuBarItemTag: CapturedImage]()
        var excluded = items

        if canCapture {
            let captureResult = await captureImages(of: items, scale: scale, appState: appState)
            images = captureResult.images
            excluded = captureResult.excluded
        }

        var failed = [MenuBarItem]()
        for item in excluded {
            if let fallback = fallbackImage(for: item, scale: scale) {
                images[item.tag] = fallback
            } else {
                failed.append(item)
            }
        }
        if !failed.isEmpty {
            logger.error("Some items failed capture and fallback: \(failed, privacy: .public)")
        }

        return images
    }

    // MARK: Hosted Items

    /// Captures the hosted items (macOS 27) laid out on the active menu
    /// bar, from `MenuBarAgent`'s window for that display.
    ///
    /// Only items whose frames held still for a moment are captured, so a
    /// reflow in progress isn't, and each at most every 20 seconds.
    @available(macOS 27.0, *)
    private func captureHostedItems(appState: AppState) async {
        let canStart = await MainActor.run {
            guard !isCapturingHostedItems else {
                return false
            }
            isCapturingHostedItems = true
            return true
        }
        guard canStart else {
            return
        }
        defer {
            Task { @MainActor in
                isCapturingHostedItems = false
            }
        }

        guard await appState.hasPermission(.screenRecording) else {
            return
        }

        let before = await appState.itemManager.itemCache
        try? await Task.sleep(for: .milliseconds(400))
        let cache = await appState.itemManager.itemCache

        guard
            await !appState.itemManager.lastMoveOperationOccurred(within: .seconds(1)),
            let displayID = cache.displayID,
            displayID == before.displayID,
            let windowID = Self.agentWindowID(for: displayID)
        else {
            return
        }

        let boundsBefore = Dictionary(before.managedItems.map { ($0.tag, $0.bounds) }) { first, _ in first }
        let stored = await MainActor.run { hostedImages }
        let now = Date()
        var captured = [MenuBarItemTag: CapturedImage]()

        for item in cache.managedItems {
            guard
                item.isHosted,
                item.isOnScreen || item.hasSlot,
                item.tag != .hiddenControlItem,
                item.tag != .alwaysHiddenControlItem,
                !item.tag.isHostedSpacer,
                item.bounds.width >= 1,
                boundsBefore[item.tag] == item.bounds,
                stored[item.tag].map({ now.timeIntervalSince($0.date) > 20 }) ?? true,
                let image = ScreenCapture.captureWindow(with: windowID, screenBounds: item.bounds, option: captureOption),
                let cutOut = Self.removingBackground(from: image)
            else {
                continue
            }
            captured[item.tag] = CapturedImage(cgImage: cutOut, scale: CGFloat(cutOut.width) / item.bounds.width)
        }

        guard !captured.isEmpty else {
            return
        }
        logger.debug("Captured \(captured.count, privacy: .public) hosted item images")
        await MainActor.run { [captured] in
            for (tag, image) in captured {
                hostedImages[tag] = (image, now)
            }
            images.merge(captured) { _, new in new }
        }
    }

    /// Returns the identifier of `MenuBarAgent`'s bar window on the given
    /// display.
    private nonisolated static func agentWindowID(for displayID: CGDirectDisplayID) -> CGWindowID? {
        guard
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: HostedMenuBarItem.agentBundleIdentifier).first,
            let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
        else {
            return nil
        }
        let displayBounds = CGDisplayBounds(displayID)
        for info in list {
            guard
                info[kCGWindowOwnerPID as String] as? pid_t == agent.processIdentifier,
                let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                bounds.origin == displayBounds.origin,
                bounds.width == displayBounds.width,
                let windowID = info[kCGWindowNumber as String] as? CGWindowID
            else {
                continue
            }
            return windowID
        }
        return nil
    }

    /// Returns the image with the menu bar's background made transparent,
    /// or `nil` if nothing but background was captured.
    ///
    /// `MenuBarAgent` draws the bar's background in the same window as the
    /// items. The background is sampled from the image's left and right
    /// edges (an item's frame includes its padding) and removed by
    /// color-to-alpha, which keeps the icon's own colors and antialiasing.
    private nonisolated static func removingBackground(from image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard
            width > 4, height > 0,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let data = context.data
        else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        var background = [Double](repeating: 0, count: 3)
        let edgeColumns = [0, 1, width - 2, width - 1]
        for y in 0..<height {
            for x in edgeColumns {
                for channel in 0..<3 {
                    background[channel] += Double(pixels[(y * width + x) * 4 + channel])
                }
            }
        }
        background = background.map { $0 / Double(height * edgeColumns.count * 255) }

        var maxAlpha = 0.0
        for index in stride(from: 0, to: width * height * 4, by: 4) {
            var alpha = 0.0
            for channel in 0..<3 {
                let value = Double(pixels[index + channel]) / 255
                let base = background[channel]
                let channelAlpha = value > base ? (value - base) / (1 - base) : (base - value) / base
                if channelAlpha.isFinite {
                    alpha = max(alpha, channelAlpha)
                }
            }
            alpha = min(alpha, 1)
            maxAlpha = max(maxAlpha, alpha)
            for channel in 0..<3 {
                // Premultiplied foreground: value − (1 − alpha) × background.
                let value = Double(pixels[index + channel]) / 255 - (1 - alpha) * background[channel]
                pixels[index + channel] = UInt8(max(0, min(alpha, value)) * 255)
            }
            pixels[index + 3] = UInt8(alpha * 255)
        }

        guard maxAlpha > 0.25 else {
            return nil
        }
        return context.makeImage()
    }

    // MARK: Update Cache

    /// Updates the cache for the given sections, without checking whether
    /// caching is necessary.
    func updateCacheWithoutChecks(sections: [MenuBarSection.Name]) async {
        guard let appState else {
            return
        }

        // Without Screen Recording, we can't capture pixel-accurate images,
        // but we can still populate the cache with app-icon fallbacks.
        let canCapture = await appState.hasPermission(.screenRecording)

        // The active menu bar display can fail to resolve in some
        // configurations (e.g. "Displays have separate Spaces" disabled).
        // Fall back to the main screen rather than skipping the cache.
        let resolvedScreen: NSScreen? = if let displayID = await appState.itemManager.itemCache.displayID {
            NSScreen.screens.first { $0.displayID == displayID } ?? NSScreen.main
        } else {
            NSScreen.main
        }
        guard let screen = resolvedScreen else {
            return
        }

        let scale = screen.backingScaleFactor
        var newImages = [MenuBarItemTag: CapturedImage]()

        for section in sections {
            guard await !appState.itemManager.itemCache[section].isEmpty else {
                continue
            }

            let sectionImages = await captureImages(for: section, scale: scale, appState: appState, canCapture: canCapture)

            guard !sectionImages.isEmpty else {
                logger.warning("Failed item image cache for \(section.logString, privacy: .public)")
                continue
            }

            newImages.merge(sectionImages) { (_, new) in new }
        }

        await MainActor.run { [newImages] in
            images.merge(newImages) { (_, new) in new }
        }
    }

    /// Updates the cache for the given sections, if necessary.
    func updateCache(sections: [MenuBarSection.Name]) async {
        guard let appState else {
            return
        }

        let isIceMeltBarPresented = await appState.navigationState.isIceMeltBarPresented
        let isSearchPresented = await appState.navigationState.isSearchPresented

        if !isIceMeltBarPresented && !isSearchPresented {
            guard
                await appState.navigationState.isAppFrontmost,
                await appState.navigationState.isSettingsPresented,
                await appState.navigationState.settingsNavigationIdentifier == .menuBarLayout
            else {
                return
            }
        }

        guard await !appState.itemManager.lastMoveOperationOccurred(within: .seconds(1)) else {
            logger.debug("Skipping item image cache due to recent item movement")
            return
        }

        await updateCacheWithoutChecks(sections: sections)
    }

    /// Updates the cache for all sections, if necessary.
    func updateCache() async {
        guard let appState else {
            return
        }

        let isIceMeltBarPresented = await appState.navigationState.isIceMeltBarPresented
        let isSearchPresented = await appState.navigationState.isSearchPresented
        let isSettingsPresented = await appState.navigationState.isSettingsPresented

        var sectionsNeedingDisplay = [MenuBarSection.Name]()

        if isSettingsPresented || isSearchPresented {
            sectionsNeedingDisplay = MenuBarSection.Name.allCases
        } else if
            isIceMeltBarPresented,
            let section = await appState.menuBarManager.iceMeltBarPanel.currentSection
        {
            sectionsNeedingDisplay.append(section)
        }

        await updateCache(sections: sectionsNeedingDisplay)
    }

    // MARK: Cache Failed

    /// Returns a Boolean value that indicates whether caching menu bar items
    /// failed for the given section.
    ///
    /// Missing Screen Recording permission is not itself a failure — the
    /// cache falls back to app icons. Failure means the section has items
    /// but not a single image could be produced for them.
    @MainActor
    func cacheFailed(for section: MenuBarSection.Name) -> Bool {
        let items = appState?.itemManager.itemCache[section] ?? []
        guard !items.isEmpty else {
            return false
        }
        let keys = Set(images.keys)
        for item in items where keys.contains(item.tag) {
            return false
        }
        return true
    }
}
