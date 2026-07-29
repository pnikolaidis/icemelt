//
//  IceMeltBarColorManager.swift
//  IceMelt
//

import Combine
import SwiftUI

final class IceMeltBarColorManager: ObservableObject {
    @Published private(set) var colorInfo: MenuBarAverageColorInfo?

    private weak var iceMeltBarPanel: IceMeltBarPanel?

    private var windowImage: CGImage?

    private var cancellables = Set<AnyCancellable>()

    func performSetup(with iceMeltBarPanel: IceMeltBarPanel) {
        self.iceMeltBarPanel = iceMeltBarPanel
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let iceMeltBarPanel {
            iceMeltBarPanel.publisher(for: \.screen)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] screen in
                    guard
                        let self,
                        let screen
                    else {
                        return
                    }
                    updateWindowImage(for: screen)
                }
                .store(in: &c)

            iceMeltBarPanel.publisher(for: \.isVisible)
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak iceMeltBarPanel] isVisible in
                    guard
                        let self,
                        let iceMeltBarPanel,
                        let screen = iceMeltBarPanel.screen,
                        isVisible
                    else {
                        return
                    }
                    updateColorInfo(with: iceMeltBarPanel.frame, screen: screen)
                }
                .store(in: &c)

            iceMeltBarPanel.publisher(for: \.frame)
                .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self, weak iceMeltBarPanel] frame in
                    guard
                        let self,
                        let iceMeltBarPanel,
                        let screen = iceMeltBarPanel.screen,
                        iceMeltBarPanel.isVisible
                    else {
                        return
                    }
                    withAnimation(.interactiveSpring) {
                        self.updateColorInfo(with: frame, screen: screen)
                    }
                }
                .store(in: &c)

            Publishers.Merge4(
                NSWorkspace.shared.notificationCenter
                    .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                    .replace(with: ()),
                NotificationCenter.default
                    .publisher(for: NSApplication.didChangeScreenParametersNotification)
                    .replace(with: ()),
                DistributedNotificationCenter.default()
                    .publisher(for: DistributedNotificationCenter.interfaceThemeChangedNotification)
                    .replace(with: ()),
                Timer.publish(every: 5, on: .main, in: .default)
                    .autoconnect()
                    .replace(with: ())
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak iceMeltBarPanel] in
                guard
                    let self,
                    let iceMeltBarPanel,
                    let screen = iceMeltBarPanel.screen
                else {
                    return
                }
                updateWindowImage(for: screen)
                if iceMeltBarPanel.isVisible {
                    withAnimation {
                        self.updateColorInfo(with: iceMeltBarPanel.frame, screen: screen)
                    }
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }

    private func updateWindowImage(for screen: NSScreen) {
        let windows = WindowInfo.createWindows(option: .onScreen)
        let displayID = screen.displayID

        guard
            let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: displayID),
            let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: displayID)
        else {
            return
        }

        guard let image = ScreenCapture.captureWindows(
            with: [menuBarWindow.windowID, wallpaperWindow.windowID],
            screenBounds: withMutableCopy(of: wallpaperWindow.bounds) { $0.size.height = 1 },
            option: .nominalResolution
        ) else {
            return
        }

        windowImage = image
    }

    private func updateColorInfo(with frame: CGRect, screen: NSScreen) {
        guard let image = windowImage else {
            return
        }

        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        let insetScreenFrame = screen.frame.insetBy(dx: frame.width / 2, dy: 0)
        let percentage = ((frame.midX - insetScreenFrame.minX) / insetScreenFrame.width).clamped(to: 0...1)

        let cropRect = CGRect(x: imageBounds.width * percentage, y: 0, width: 0, height: 1)
            .insetBy(dx: -150, dy: 0)
            .intersection(imageBounds)

        guard
            let croppedImage = image.cropping(to: cropRect),
            let averageColor = croppedImage.averageColor()
        else {
            return
        }

        // Just use `menuBarWindow` as the source for now, regardless
        // of whether its image contributed to the average.
        colorInfo = MenuBarAverageColorInfo(color: averageColor, source: .menuBarWindow)
    }

    func updateAllProperties(with frame: CGRect, screen: NSScreen) {
        updateWindowImage(for: screen)
        updateColorInfo(with: frame, screen: screen)
    }
}
