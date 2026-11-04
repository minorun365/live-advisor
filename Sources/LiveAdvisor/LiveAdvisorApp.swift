import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// A borderless panel so the surface is pure white and clicking it never takes focus from the meeting.
final class AdvisorWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = AdvisorEngine()
    private var statusItem: NSStatusItem!
    private var panel: AdvisorWindow!
    private var outsideClickMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()
    private var contentHeight: CGFloat = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let isInstalled = Bundle.main.bundleURL.path.hasPrefix(
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        )

        if isInstalled, NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").count > 1 {
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.toolTip = "助言さん"
        Publishers.CombineLatest(engine.$phase, engine.$hasUnread)
            .sink { [weak self] phase, unread in
                let state = AdvisorPolicy.menuBarState(isRunning: phase == .running, hasUnread: unread)
                let image = NSImage(named: state.imageName)
                image?.isTemplate = state.isTemplate
                self?.statusItem.button?.image = image
            }
            .store(in: &subscriptions)

        panel = makePanel()
        engine.$allowsCapture
            .sink { [weak self] allowed in self?.panel.sharingType = allowed ? .readOnly : .none }
            .store(in: &subscriptions)
        engine.start()

        if isInstalled {
            try? SMAppService.mainApp.register()
        }

        #if DEBUG
        if arguments.contains("--fixture") { engine.loadFixture() }
        if arguments.contains("--allow-capture") { engine.allowsCapture = true }
        if let flag = arguments.firstIndex(of: "--menu-preview"), arguments.indices.contains(flag + 1) {
            engine.previewMenuBar(arguments[flag + 1])
        }
        if let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(flag + 1) {
            let path = arguments[flag + 1]
            panel.setFrameOrigin(NSPoint(x: -4000, y: 200))
            panel.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.writeSnapshot(to: path)
                NSApp.terminate(nil)
            }
            return
        }
        #endif
        if arguments.contains("--open") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.showPanel() }
        }
    }

    private func makePanel() -> AdvisorWindow {
        let panel = AdvisorWindow(
            contentRect: NSRect(x: 0, y: 0, width: AdvisorPanel.width, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.sharingType = .none

        let host = NSHostingView(rootView: AdvisorPanel(
            engine: engine,
            onQuit: { NSApp.terminate(nil) },
            onHeightChange: { [weak self] height in self?.contentHeight = height; self?.reposition() },
            expandsAllCards: ProcessInfo.processInfo.arguments.contains("--expand-all")
        ))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    #if DEBUG
    private func writeSnapshot(to path: String) {
        guard let host = panel.contentView else { return }
        host.setFrameSize(NSSize(width: AdvisorPanel.width, height: contentHeight))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    #endif

    @objc private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        engine.panelOpened()
        panel.orderFrontRegardless()
        reposition()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            // The click that takes a screenshot must not close what is being photographed.
            Task { @MainActor in
                guard self?.engine.allowsCapture == false else { return }
                self?.hidePanel()
            }
        }
    }

    private func hidePanel() {
        engine.allowsCapture = false
        panel.orderOut(nil)
        engine.panelClosed()
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    /// Keeps the top edge under the menu bar icon while the content grows or shrinks.
    private func reposition() {
        guard panel?.isVisible == true, panel.frame.minX > -1000,
              let button = statusItem?.button, let window = button.window, let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.frame)
        let size = NSSize(width: AdvisorPanel.width, height: contentHeight)
        let x = min(max(anchor.midX - size.width / 2, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: anchor.minY - 6 - size.height, width: size.width, height: size.height), display: true)
    }
}

@main
enum LiveAdvisorMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
