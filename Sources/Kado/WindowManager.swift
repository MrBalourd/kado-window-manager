import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
import ServiceManagement

enum WindowLayout: String, CaseIterable, Identifiable, Codable {
    case grid, columns
    var id: String { rawValue }
    var title: String { self == .grid ? "Grid" : "Columns" }
}

enum OverflowMode: String, CaseIterable, Identifiable {
    case stack, float
    var id: String { rawValue }
    var title: String { self == .stack ? "Stack in the active tile" : "Float in the middle" }
}

enum HighlightStyle: String, CaseIterable, Identifiable {
    case none, activeBorder, allBorders, glow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .activeBorder: "Active border"
        case .allBorders: "All borders"
        case .glow: "Glow on active"
        }
    }
}

enum CleanBackground: String, CaseIterable, Identifiable {
    case graphite, mist, stone
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: NSColor {
        switch self {
        case .graphite: NSColor(calibratedWhite: 0.12, alpha: 1)
        case .mist: NSColor(calibratedWhite: 0.88, alpha: 1)
        case .stone: NSColor(calibratedRed: 0.60, green: 0.57, blue: 0.52, alpha: 1)
        }
    }
}

enum AppIconStyle: String, CaseIterable, Identifiable {
    case sand, amber, blue, midnight, vermilion, spectrum, graphite
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var background: NSColor {
        switch self {
        case .sand: NSColor(calibratedRed: 0.91, green: 0.89, blue: 0.83, alpha: 1)
        case .amber: NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.07, alpha: 1)
        case .blue: NSColor(calibratedRed: 0.12, green: 0.36, blue: 0.91, alpha: 1)
        case .midnight: NSColor(calibratedRed: 0.08, green: 0.07, blue: 0.15, alpha: 1)
        case .vermilion: NSColor(calibratedRed: 0.90, green: 0.22, blue: 0.13, alpha: 1)
        case .spectrum: NSColor(calibratedRed: 0.31, green: 0.23, blue: 0.83, alpha: 1)
        case .graphite: NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.16, alpha: 1)
        }
    }
    var tiles: [NSColor] {
        switch self {
        case .sand: return ["#222b38", "#2583ff", "#687687"].map { NSColor(hex: $0) }
        case .amber: return Array(repeating: NSColor(calibratedRed: 1, green: 0.73, blue: 0.36, alpha: 1), count: 3)
        case .blue: return Array(repeating: NSColor(calibratedWhite: 0.94, alpha: 1), count: 3)
        case .midnight: return ["#ff6f8f", "#ffbd65", "#a66cff"].map { NSColor(hex: $0) }
        case .vermilion: return Array(repeating: NSColor(calibratedWhite: 0.98, alpha: 1), count: 3)
        case .spectrum: return ["#ff7d8d", "#ffbe58", "#71a8ff"].map { NSColor(hex: $0) }
        case .graphite: return ["#5592ff", "#283241", "#536071"].map { NSColor(hex: $0) }
        }
    }
}

struct ScreenLayoutSettings: Codable, Equatable {
    var layout: WindowLayout
    var windowLimit: Int
    var gap: Int
}

struct DisplayPreference: Identifiable {
    let id: String
    let index: Int
    let name: String
    let frame: CGRect
    let layout: WindowLayout
    let windowLimit: Int
    let gap: Int
}

struct AppPreferenceItem: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    let excluded: Bool
}

struct ManagedWindow: Identifiable {
    let id: String
    let element: AXUIElement
    let pid: pid_t
    let bounds: CGRect
    let screenIndex: Int
    let isFocused: Bool
    let isMovable: Bool
    let bundleIdentifier: String?
    let appName: String?
    let appIcon: NSImage?
}

private struct OnScreenWindowSnapshot {
    let framesByPID: [pid_t: [CGRect]]
    let processOrder: [pid_t]
}

struct TabWindowItem: Identifiable {
    let id: String
    let element: AXUIElement
    let pid: pid_t
    let screenIndex: Int
    let appName: String
    let icon: NSImage?
    let frame: CGRect
}

struct MenuWindowItem: Identifiable {
    let id: String
    let screenIndex: Int
    let appName: String
    let icon: NSImage?
    let bundleIdentifier: String?
    let isFocused: Bool
}

private struct SavedWindowFrame {
    let element: AXUIElement
    let frame: CGRect
}

private struct RunningAppMetadata {
    let bundleIdentifier: String?
    let name: String?
    let icon: NSImage?
}

private struct DragWindowSnapshot {
    let id: String
    let element: AXUIElement
    let frame: CGRect
    let screenIndex: Int
}

@MainActor
final class WindowManager: ObservableObject {
    static let shared = WindowManager()

    static let accents: [String: NSColor] = [
        "Blue": NSColor(calibratedRed: 0.04, green: 0.49, blue: 1, alpha: 1),
        "Purple": NSColor(calibratedRed: 0.65, green: 0.30, blue: 0.96, alpha: 1),
        "Pink": NSColor(calibratedRed: 0.94, green: 0.22, blue: 0.51, alpha: 1),
        "Orange": NSColor(calibratedRed: 1, green: 0.58, blue: 0, alpha: 1),
        "Green": NSColor(calibratedRed: 0.19, green: 0.78, blue: 0.36, alpha: 1),
        "Graphite": NSColor(calibratedWhite: 0.55, alpha: 1)
    ]

    @Published private(set) var hasAccessibility = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
    @Published private(set) var statusMessage: String?
    @Published private(set) var isEnabled = UserDefaults.standard.object(forKey: "tilingEnabled") as? Bool ?? false
    @Published private(set) var openAtLogin = UserDefaults.standard.bool(forKey: "openAtLogin")
    @Published private(set) var layout = WindowLayout(rawValue: UserDefaults.standard.string(forKey: "layout") ?? "grid") ?? .grid
    @Published private(set) var overflowMode = OverflowMode(rawValue: UserDefaults.standard.string(forKey: "overflowMode") ?? "stack") ?? .stack
    @Published private(set) var highlight = HighlightStyle(rawValue: UserDefaults.standard.string(forKey: "highlight") ?? "none") ?? .none
    @Published private(set) var windowLimit = min(4, max(1, UserDefaults.standard.integer(forKey: "windowLimit").nonZero(or: 3)))
    @Published private(set) var gap = min(24, max(0, UserDefaults.standard.object(forKey: "gap") as? Int ?? 8))
    @Published private(set) var accentName = UserDefaults.standard.string(forKey: "accent") ?? "Blue"
    @Published private(set) var appIconStyle = AppIconStyle(rawValue: UserDefaults.standard.string(forKey: "appIconStyle") ?? "sand") ?? .sand
    @Published private(set) var keyboardShortcutsEnabled = UserDefaults.standard.object(forKey: "keyboardShortcutsEnabled") as? Bool ?? true
    @Published private(set) var noPeekBlurEnabled = UserDefaults.standard.object(forKey: "noPeekBlur") as? Bool ?? true
    @Published private(set) var excludedApps = Set(UserDefaults.standard.stringArray(forKey: "excludedApps") ?? [])
    @Published private(set) var menuWindows: [MenuWindowItem] = []
    @Published private(set) var hoverFocusEnabled = UserDefaults.standard.bool(forKey: "hoverFocusEnabled")
    @Published private(set) var perScreenSettings = WindowManager.loadScreenSettings()
    @Published private(set) var tabViewActive = false
    @Published private(set) var tabViewItems: [TabWindowItem] = []
    @Published private(set) var noPeekActive = false
    @Published private(set) var noPeekDimAmount = min(90, max(10, UserDefaults.standard.object(forKey: "noPeekDim") as? Int ?? 50))
    @Published private(set) var cleanSpaceActive = false
    @Published private(set) var cleanBackground = CleanBackground(rawValue: UserDefaults.standard.string(forKey: "cleanBackground") ?? "graphite") ?? .graphite

    var accessibilitySettingsName: String {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"
    }

    var accessibilityPermissionHelp: String {
        "Enable Kado under System Settings → Privacy & Security → \(accessibilitySettingsName). If its switch is already on, remove the old Kado entry with −, add this Kado.app again, enable it, then quit and reopen Kado."
    }

    private var timer: Timer?
    private var pendingImmediatePoll: DispatchWorkItem?
    private var lastIdlePollDate = Date.distantPast
    private var previousWindowIDs = Set<String>()
    private var overlays: [String: WindowOutline] = [:]
    private var appMetadataCache: [pid_t: RunningAppMetadata] = [:]
    private var lastFocusedID: String?
    private var lastHoverFocusedID: String?
    private var didInitialTile = false
    private var hotKeyHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var didInstallHotKeyHandler = false
    private var mouseSwapMonitor: Any?
    private var dragSource: DragWindowSnapshot?
    private var dragWindows: [DragWindowSnapshot] = []
    private var dragOrigin: CGPoint?
    private var dragMoved = false
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var tabPanel: TabPickerPanel?
    private var noPeekPanels: [Int: NoPeekPanel] = [:]
    private var noPeekFocusRects: [Int: CGRect] = [:]
    private var pendingNoPeekActivation: DispatchWorkItem?
    private var cleanPanel: CleanSpacePanel?
    private var cleanScreenIndex: Int?
    private var cleanSavedFrames: [String: SavedWindowFrame] = [:]

    private static func loadScreenSettings() -> [String: ScreenLayoutSettings] {
        guard let data = UserDefaults.standard.data(forKey: "perScreenSettings"),
              let values = try? JSONDecoder().decode([String: ScreenLayoutSettings].self, from: data) else { return [:] }
        return values
    }

    var displayPreferences: [DisplayPreference] {
        NSScreen.screens.enumerated().map { index, screen in
            let id = displayID(screen, index: index)
            let values = perScreenSettings[id] ?? ScreenLayoutSettings(layout: layout, windowLimit: windowLimit, gap: gap)
            return DisplayPreference(id: id, index: index, name: screen.localizedName, frame: screen.frame,
                                     layout: values.layout, windowLimit: values.windowLimit, gap: values.gap)
        }
    }

    var appPreferences: [AppPreferenceItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID && $0.bundleIdentifier != nil }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return AppPreferenceItem(id: bundleID, name: app.localizedName ?? bundleID, icon: app.icon,
                                         excluded: excludedApps.contains(bundleID))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    init() {
        installShortcuts()
        installLifecycleObservers()
        if isEnabled && hasAccessibility { updateMonitoring() }
    }

    private func installLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let events: [Notification.Name] = [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification]
        for event in events {
            lifecycleObservers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated { self.endTransientModes() }
            })
        }
        lifecycleObservers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.handleActiveSpaceChange() }
        })
        for event in [NSWorkspace.didActivateApplicationNotification,
                      NSWorkspace.didLaunchApplicationNotification,
                      NSWorkspace.didTerminateApplicationNotification] {
            lifecycleObservers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.scheduleImmediatePoll(after: event == NSWorkspace.didLaunchApplicationNotification ? 0.25 : 0.08)
                }
            })
        }
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.shutdown() }
        })
    }

    private func endTransientModes() {
        if cleanSpaceActive { closeCleanSpace() }
        closeNoPeek()
        closeTabView()
    }

    private func handleActiveSpaceChange() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.hasAccessibility else { return }
            if self.cleanSpaceActive { self.closeCleanSpace() }
            if self.tabViewActive { self.closeTabView() }
            self.didInitialTile = false
            self.previousWindowIDs.removeAll()
            let windows = self.collectWindows()
            self.updateMenuWindows(from: windows)
            if self.isEnabled { self.tidyNow() }
            if self.noPeekActive { self.updateNoPeek(windows: windows) }
        }
    }

    private func shutdown() {
        endTransientModes()
        clearOutlines()
        stopMonitoring()
        removeMouseSwapMonitor()
        unregisterShortcuts()
    }

    func quitKado() {
        shutdown()
        NSApp.terminate(self)
    }

    func refreshPermission() {
        let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
        let changed = hasAccessibility != trusted
        if changed { hasAccessibility = trusted }
        if !trusted {
            if isEnabled { isEnabled = false }
            if changed {
                stopMonitoring()
                clearOutlines()
                closeNoPeek()
                closeTabView()
            }
        } else if changed {
            isEnabled = UserDefaults.standard.bool(forKey: "tilingEnabled")
            updateMonitoring()
        }
    }

    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        openAccessibilitySettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshPermission() }
    }

    func openAccessibilitySettings() {
        let urlString: String
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 13 {
            urlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        } else {
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }

    func checkAccessibilityPermission() {
        refreshPermission()
        if !hasAccessibility { statusMessage = accessibilityPermissionHelp }
    }

    func setEnabled(_ enabled: Bool) {
        refreshPermission()
        guard hasAccessibility || !enabled else {
            statusMessage = "Allow Kado under System Settings → Privacy & Security → Accessibility."
            requestAccessibility()
            return
        }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "tilingEnabled")
        if enabled {
            didInitialTile = false
            updateMonitoring()
            tidyNow()
        } else {
            clearOutlines()
            updateMonitoring()
            statusMessage = "Automatic tiling is paused. Your windows stay where they are."
        }
    }

    func setLayout(_ value: WindowLayout) { layout = value; UserDefaults.standard.set(value.rawValue, forKey: "layout"); applyLayoutIfNeeded() }
    func setOverflowMode(_ value: OverflowMode) { overflowMode = value; UserDefaults.standard.set(value.rawValue, forKey: "overflowMode"); applyLayoutIfNeeded() }
    func setHighlight(_ value: HighlightStyle) {
        highlight = value
        UserDefaults.standard.set(value.rawValue, forKey: "highlight")
        updateMonitoring()
        updateOutlines()
    }
    func setWindowLimit(_ value: Int) { windowLimit = min(4, max(1, value)); UserDefaults.standard.set(windowLimit, forKey: "windowLimit"); applyLayoutIfNeeded() }
    func setGap(_ value: Int) { gap = min(24, max(0, value)); UserDefaults.standard.set(gap, forKey: "gap"); applyLayoutIfNeeded() }
    func setAccent(_ value: String) { accentName = Self.accents[value] == nil ? "Blue" : value; UserDefaults.standard.set(accentName, forKey: "accent"); updateOutlines() }
    func setAppIconStyle(_ value: AppIconStyle) { appIconStyle = value; UserDefaults.standard.set(value.rawValue, forKey: "appIconStyle") }
    func setKeyboardShortcutsEnabled(_ enabled: Bool) {
        guard keyboardShortcutsEnabled != enabled else { return }
        keyboardShortcutsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "keyboardShortcutsEnabled")
        if enabled { registerShortcuts() } else { unregisterShortcuts() }
    }
    func setNoPeekBlurEnabled(_ enabled: Bool) {
        guard noPeekBlurEnabled != enabled else { return }
        noPeekBlurEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "noPeekBlur")
        renderNoPeek()
    }
    func setHoverFocusEnabled(_ enabled: Bool) {
        guard hoverFocusEnabled != enabled else { return }
        refreshPermission()
        guard hasAccessibility || !enabled else {
            statusMessage = "Grant Accessibility access to use Hover focus."
            requestAccessibility()
            return
        }
        hoverFocusEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "hoverFocusEnabled")
        if !enabled { lastHoverFocusedID = nil }
        updateMonitoring()
    }
    func setNoPeekDimAmount(_ value: Int) {
        let clampedValue = min(90, max(10, value))
        guard noPeekDimAmount != clampedValue else { return }
        noPeekDimAmount = clampedValue
        UserDefaults.standard.set(noPeekDimAmount, forKey: "noPeekDim")
        renderNoPeek()
    }
    func setCleanBackground(_ value: CleanBackground) { cleanBackground = value; UserDefaults.standard.set(value.rawValue, forKey: "cleanBackground"); cleanPanel?.setBackground(value.color) }

    func setScreenLayout(_ value: WindowLayout, id: String) { updateScreenSettings(id) { $0.layout = value } }
    func setScreenWindowLimit(_ value: Int, id: String) { updateScreenSettings(id) { $0.windowLimit = min(4, max(1, value)) } }
    func setScreenGap(_ value: Int, id: String) { updateScreenSettings(id) { $0.gap = min(24, max(0, value)) } }

    func layoutForScreen(at index: Int) -> WindowLayout {
        guard NSScreen.screens.indices.contains(index) else { return layout }
        return layoutSettings(for: NSScreen.screens[index], index: index).layout
    }

    func windowLimitForScreen(at index: Int) -> Int {
        guard NSScreen.screens.indices.contains(index) else { return windowLimit }
        return layoutSettings(for: NSScreen.screens[index], index: index).windowLimit
    }

    func setLayout(_ value: WindowLayout, forScreenAt index: Int) {
        guard NSScreen.screens.indices.contains(index) else { setLayout(value); return }
        setScreenLayout(value, id: displayID(NSScreen.screens[index], index: index))
    }

    func setWindowLimit(_ value: Int, forScreenAt index: Int) {
        guard NSScreen.screens.indices.contains(index) else { setWindowLimit(value); return }
        setScreenWindowLimit(value, id: displayID(NSScreen.screens[index], index: index))
    }

    private func updateScreenSettings(_ id: String, update: (inout ScreenLayoutSettings) -> Void) {
        var values = perScreenSettings[id] ?? ScreenLayoutSettings(layout: layout, windowLimit: windowLimit, gap: gap)
        update(&values)
        perScreenSettings[id] = values
        if let data = try? JSONEncoder().encode(perScreenSettings) { UserDefaults.standard.set(data, forKey: "perScreenSettings") }
        applyLayoutIfNeeded()
    }

    func setAppExcluded(_ bundleID: String, excluded: Bool) {
        if excluded { excludedApps.insert(bundleID) } else { excludedApps.remove(bundleID) }
        UserDefaults.standard.set(Array(excludedApps).sorted(), forKey: "excludedApps")
        applyLayoutIfNeeded()
    }

    func toggleAppExcluded(_ bundleID: String) { setAppExcluded(bundleID, excluded: !excludedApps.contains(bundleID)) }

    func refreshMenuWindows() {
        refreshPermission()
        guard hasAccessibility else { updateMenuWindows(from: []); return }
        updateMenuWindows(from: collectWindows())
    }

    func focusMenuWindow(_ id: String) {
        guard let window = collectWindows().first(where: { $0.id == id }) else { return }
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        refreshMenuWindows()
    }

    func columnCapacity(for screenIndex: Int) -> Int {
        guard NSScreen.screens.indices.contains(screenIndex) else { return 1 }
        return min(4, max(1, Int(NSScreen.screens[screenIndex].visibleFrame.width / 420)))
    }

    var menuScreenIndex: Int {
        let point = NSEvent.mouseLocation
        if let pointerScreen = NSScreen.screens.firstIndex(where: { $0.frame.contains(point) }) { return pointerScreen }
        return menuWindows.first(where: \.isFocused)?.screenIndex ?? 0
    }

    private func applyLayoutIfNeeded() {
        if isEnabled && !cleanSpaceActive { tidyNow() }
    }

    private func updateMonitoring() {
        updateMouseSwapMonitoring()
        if hasAccessibility && (isEnabled || noPeekActive || cleanSpaceActive || highlight != .none || hoverFocusEnabled) { startMonitoring() }
        else { stopMonitoring() }
    }

    private func updateMouseSwapMonitoring() {
        guard hasAccessibility && isEnabled else {
            removeMouseSwapMonitor()
            return
        }
        guard mouseSwapMonitor == nil else { return }
        mouseSwapMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let type = event.type
            let modifiers = event.modifierFlags
            let point = NSEvent.mouseLocation
            Task { @MainActor in self?.handleMouseSwapEvent(type: type, modifiers: modifiers, point: point) }
        }
    }

    private func removeMouseSwapMonitor() {
        if let mouseSwapMonitor { NSEvent.removeMonitor(mouseSwapMonitor) }
        mouseSwapMonitor = nil
        resetMouseSwapDrag()
    }

    private func handleMouseSwapEvent(type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags, point: CGPoint) {
        switch type {
        case .leftMouseDown:
            guard hasAccessibility, isEnabled, !cleanSpaceActive, !tabViewActive,
                  modifiers.contains(.command) else {
                resetMouseSwapDrag()
                return
            }
            let windows = collectWindows().filter(isTileEligible)
            let snapshots = windows.map { window in
                DragWindowSnapshot(id: window.id, element: window.element, frame: appKitFrame(for: window), screenIndex: window.screenIndex)
            }
            guard let source = snapshots.first(where: { $0.frame.contains(point) }) else {
                resetMouseSwapDrag()
                return
            }
            dragWindows = snapshots
            dragSource = source
            dragOrigin = point
            dragMoved = false

        case .leftMouseDragged:
            guard let dragOrigin else { return }
            if hypot(point.x - dragOrigin.x, point.y - dragOrigin.y) >= 4 { dragMoved = true }

        case .leftMouseUp:
            guard let source = dragSource, dragMoved else {
                resetMouseSwapDrag()
                return
            }
            let target = dragWindows.first {
                $0.id != source.id && $0.screenIndex == source.screenIndex && $0.frame.contains(point)
            }
            if let target {
                move(source.element, to: target.frame)
                move(target.element, to: source.frame)
                lastFocusedID = source.id
                updateOutlines()
            }
            resetMouseSwapDrag()

        default:
            break
        }
    }

    private func resetMouseSwapDrag() {
        dragSource = nil
        dragWindows.removeAll()
        dragOrigin = nil
        dragMoved = false
    }

    func toggleTabView() {
        if tabViewActive { closeTabView(); return }
        refreshPermission()
        guard hasAccessibility else { statusMessage = "Allow Accessibility access to open the window switcher."; requestAccessibility(); return }
        if cleanSpaceActive { closeCleanSpace() }
        let windows = collectWindows()
        guard !windows.isEmpty else { statusMessage = "No windows are available to switch to."; return }
        tabViewItems = windows.map { window in
            let screenFrame = NSScreen.screens[window.screenIndex].visibleFrame
            let appFrame = appKitFrame(for: window)
            let normalized = CGRect(
                x: (appFrame.minX - screenFrame.minX) / max(screenFrame.width, 1),
                y: 1 - (appFrame.maxY - screenFrame.minY) / max(screenFrame.height, 1),
                width: appFrame.width / max(screenFrame.width, 1),
                height: appFrame.height / max(screenFrame.height, 1)
            )
            return TabWindowItem(id: window.id, element: window.element, pid: window.pid, screenIndex: window.screenIndex,
                                 appName: window.appName ?? "App", icon: window.appIcon, frame: normalized)
        }
        tabViewActive = true
        tabPanel = TabPickerPanel(manager: self)
        tabPanel?.show()
    }

    func closeTabView() {
        tabViewActive = false
        tabPanel?.close()
        tabPanel = nil
        tabViewItems.removeAll()
    }

    func selectTabWindow(_ id: String) {
        guard let item = tabViewItems.first(where: { $0.id == id }) else { return }
        NSRunningApplication(processIdentifier: item.pid)?.activate(options: [])
        AXUIElementPerformAction(item.element, kAXRaiseAction as CFString)
        closeTabView()
    }

    func selectCurrentTabWindow() {
        guard let id = tabPanel?.selectedID ?? tabViewItems.first?.id else { return }
        selectTabWindow(id)
    }

    func moveTabSelection(_ direction: Int) {
        guard tabViewActive, !tabViewItems.isEmpty else { return }
        let current = tabPanel?.selectedID.flatMap { id in tabViewItems.firstIndex(where: { $0.id == id }) } ?? 0
        let next = (current + direction + tabViewItems.count) % tabViewItems.count
        tabPanel?.selectedID = tabViewItems[next].id
    }

    func toggleCleanSpace() {
        if cleanSpaceActive { closeCleanSpace(); return }
        refreshPermission()
        guard hasAccessibility else { statusMessage = "Allow Accessibility access to use presentation mode."; requestAccessibility(); return }
        closeTabView()
        guard !NSScreen.screens.isEmpty else { statusMessage = "No display is available for presentation mode."; return }
        let windows = collectWindows()
        let active = windows.first(where: { $0.isFocused && $0.isMovable })
        guard active != nil else {
            statusMessage = "Presentation mode needs a focused window that can be resized."
            return
        }
        let screenIndex = active?.screenIndex ?? screenUnderPointer()
        cleanScreenIndex = screenIndex
        cleanSavedFrames.removeAll()
        cleanPanel = CleanSpacePanel(screen: NSScreen.screens[screenIndex], background: cleanBackground.color)
        cleanPanel?.show()
        cleanSpaceActive = true
        updateMonitoring()
        clearOutlines()
        if let active { fillCleanSpace(with: active) }
        statusMessage = "Presentation mode is active on this display."
    }

    func closeCleanSpace() {
        guard cleanSpaceActive else { return }
        cleanSpaceActive = false
        cleanPanel?.close()
        cleanPanel = nil
        for saved in cleanSavedFrames.values { move(saved.element, to: saved.frame) }
        cleanSavedFrames.removeAll()
        cleanScreenIndex = nil
        updateMonitoring()
        if highlight != .none { updateOutlines() }
        statusMessage = "Presentation mode is off. Window positions have been restored."
    }

    func toggleNoPeek() {
        if noPeekActive { closeNoPeek(); return }
        if let pendingNoPeekActivation {
            pendingNoPeekActivation.cancel()
            self.pendingNoPeekActivation = nil
            return
        }
        refreshPermission()
        guard hasAccessibility else { statusMessage = "Grant Accessibility access to use No peek."; requestAccessibility(); return }
        closeTabView()
        // Leave the current menu/hotkey event before mutating the SwiftUI popover and
        // ordering overlay panels. Updating NSHostingView during AppKit hit-testing can
        // dereference a stale currentEvent on macOS 27.
        let activation = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingNoPeekActivation = nil
            guard !self.noPeekActive else { return }
            self.noPeekActive = true
            self.updateMonitoring()
            self.updateNoPeek()
            self.statusMessage = self.noPeekBlurEnabled
                ? "No peek is on. Other windows are dimmed and blurred."
                : "No peek is on. Other windows are dimmed."
        }
        pendingNoPeekActivation = activation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: activation)
    }

    func closeNoPeek() {
        pendingNoPeekActivation?.cancel()
        pendingNoPeekActivation = nil
        noPeekActive = false
        noPeekPanels.values.forEach { $0.close() }
        noPeekPanels.removeAll()
        noPeekFocusRects.removeAll()
        updateMonitoring()
    }

    func tabPanelDidClose() {
        tabPanel = nil
        tabViewActive = false
        tabViewItems.removeAll()
    }

    func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            openAtLogin = enabled
            UserDefaults.standard.set(enabled, forKey: "openAtLogin")
            statusMessage = enabled ? "Kado will open when you log in." : "Open at login is off."
        } catch {
            statusMessage = "Could not change Open at Login. Use System Settings → General → Login Items."
        }
    }

    func tidyNow() {
        if cleanSpaceActive { closeCleanSpace() }
        refreshPermission()
        guard hasAccessibility else {
            statusMessage = "Grant Accessibility access before arranging windows."
            return
        }
        let windows = collectWindows().filter(isTileEligible)
        guard !windows.isEmpty else {
            previousWindowIDs.removeAll()
            didInitialTile = true
            updateOutlines()
            statusMessage = "No resizable windows to arrange."
            return
        }
        var usedGridFallback = false
        for screenIndex in NSScreen.screens.indices {
            let group = windows.filter { $0.screenIndex == screenIndex }
            guard !group.isEmpty else { continue }
            let screen = NSScreen.screens[screenIndex]
            let screenConfig = layoutSettings(for: screen, index: screenIndex)
            let insetX = min(CGFloat(screenConfig.gap), max(0, (screen.visibleFrame.width - 1) / 2))
            let insetY = min(CGFloat(screenConfig.gap), max(0, (screen.visibleFrame.height - 1) / 2))
            let usable = screen.visibleFrame.insetBy(dx: insetX, dy: insetY)
            let count = min(group.count, screenConfig.windowLimit)
            let isTall = screen.visibleFrame.height > screen.visibleFrame.width
            var frames = tileFrames(in: usable, count: count, layout: screenConfig.layout, gap: screenConfig.gap, isTall: isTall)
            var adaptiveColumnsApplied = false
            if screenConfig.layout == .columns, !isTall, count > 1 {
                if let fitted = fitColumnFrames(for: Array(group.prefix(count)), in: usable, gap: screenConfig.gap) {
                    frames = fitted
                    adaptiveColumnsApplied = true
                } else {
                    // Some apps enforce minimum widths. A grid gives each window more
                    // horizontal room than equal columns and keeps the windows visible.
                    frames = tileFrames(in: usable, count: count, layout: .grid, gap: screenConfig.gap, isTall: false)
                    usedGridFallback = true
                }
            }
            for (index, window) in group.enumerated() {
                let frame: CGRect
                if index < frames.count {
                    frame = frames[index]
                } else if overflowMode == .stack {
                    let focusedIndex = group.firstIndex(where: \.isFocused) ?? 0
                    frame = frames[min(focusedIndex, frames.count - 1)]
                } else {
                    let size = CGSize(width: min(usable.width * 0.7, 900), height: min(usable.height * 0.7, 650))
                    frame = CGRect(x: usable.midX - size.width / 2, y: usable.midY - size.height / 2, width: size.width, height: size.height)
                }
                if !adaptiveColumnsApplied || index >= count {
                    move(window.element, to: frame)
                }
            }
        }
        previousWindowIDs = Set(windows.map(\.id))
        didInitialTile = true
        statusMessage = usedGridFallback
            ? "Some windows could not fit in Columns at their minimum widths, so Kado used Grid to keep them visible."
            : "Tiled \(windows.count) window\(windows.count == 1 ? "" : "s") across \(Set(windows.map(\.screenIndex)).count) screen\(Set(windows.map(\.screenIndex)).count == 1 ? "" : "s")."
        updateOutlines()
    }

    private func startMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollWindows() }
        }
    }

    private func stopMonitoring() { timer?.invalidate(); timer = nil }

    private func installShortcuts() {
        guard !didInstallHotKeyHandler else { return }
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            var hotKeyID = EventHotKeyID()
            let size = MemoryLayout<EventHotKeyID>.size
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, size, nil, &hotKeyID)
            guard status == noErr else { return noErr }
            let manager = Unmanaged<WindowManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in manager.handleShortcut(hotKeyID.id) }
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        guard result == noErr else { return }
        didInstallHotKeyHandler = true

        if keyboardShortcutsEnabled { registerShortcuts() }
    }

    private func registerShortcuts() {
        guard didInstallHotKeyHandler, keyboardShortcutsEnabled, hotKeyRefs.isEmpty else { return }
        let layoutKeys: [(UInt32, UInt32)] = [
            (UInt32(kVK_ANSI_1), UInt32(controlKey | optionKey | cmdKey)),
            (UInt32(kVK_ANSI_2), UInt32(controlKey | optionKey | cmdKey)),
            (UInt32(kVK_ANSI_3), UInt32(controlKey | optionKey | cmdKey)),
            (UInt32(kVK_ANSI_4), UInt32(controlKey | optionKey | cmdKey))
        ]
        for (offset, shortcut) in layoutKeys.enumerated() {
            registerShortcut(keyCode: shortcut.0, modifiers: shortcut.1, id: UInt32(offset + 1))
        }
        let arrows: [(UInt32, UInt32)] = [
            (UInt32(kVK_LeftArrow), 11), (UInt32(kVK_RightArrow), 12),
            (UInt32(kVK_UpArrow), 13), (UInt32(kVK_DownArrow), 14)
        ]
        for (keyCode, id) in arrows {
            registerShortcut(keyCode: keyCode, modifiers: UInt32(controlKey | optionKey), id: id)
        }
        registerShortcut(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey), id: 20)
        registerShortcut(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey | shiftKey), id: 21)
        registerShortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey), id: 30)
        registerShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey), id: 31)
    }

    private func unregisterShortcuts() {
        for reference in hotKeyRefs { UnregisterEventHotKey(reference) }
        hotKeyRefs.removeAll()
    }

    private func registerShortcut(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: OSType(0x53484F4A), id: id)
        guard RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &reference) == noErr,
              let reference else { return }
        hotKeyRefs.append(reference)
    }

    private func handleShortcut(_ id: UInt32) {
        guard keyboardShortcutsEnabled else { return }
        if (1...4).contains(id) {
            windowLimit = Int(id)
            UserDefaults.standard.set(windowLimit, forKey: "windowLimit")
            if let focused = collectWindows().first(where: \.isFocused), let screen = NSScreen.screens[safe: focused.screenIndex] {
                setScreenWindowLimit(Int(id), id: displayID(screen, index: focused.screenIndex))
                if !isEnabled { setEnabled(true) } else { tidyNow() }
            } else if isEnabled { tidyNow() } else { setEnabled(true) }
        } else if id == 20 {
            if tabViewActive { moveTabSelection(1) } else { toggleTabView() }
        } else if id == 21 {
            if tabViewActive { moveTabSelection(-1) } else { toggleTabView() }
        } else if id == 30 {
            toggleCleanSpace()
        } else if id == 31 {
            toggleNoPeek()
        } else {
            let direction: Direction
            switch id {
            case 11: direction = .left
            case 12: direction = .right
            case 13: direction = .up
            case 14: direction = .down
            default: return
            }
            swapFocusedWindow(direction)
        }
    }

    private enum Direction { case left, right, up, down }

    private func swapFocusedWindow(_ direction: Direction) {
        refreshPermission()
        guard hasAccessibility, isEnabled else { return }
        let windows = collectWindows().filter(isTileEligible)
        guard let active = windows.first(where: \.isFocused) else { return }
        let primaryTop = NSScreen.main?.frame.maxY ?? 0
        func screenRect(_ window: ManagedWindow) -> CGRect {
            CGRect(x: window.bounds.minX, y: primaryTop - window.bounds.maxY, width: window.bounds.width, height: window.bounds.height)
        }
        let activeRect = screenRect(active), center = CGPoint(x: activeRect.midX, y: activeRect.midY)
        let candidates = windows.filter { $0.id != active.id && $0.screenIndex == active.screenIndex }.compactMap { window -> (ManagedWindow, CGRect, CGFloat)? in
            let rect = screenRect(window), point = CGPoint(x: rect.midX, y: rect.midY)
            let dx = point.x - center.x, dy = point.y - center.y
            let valid: Bool
            let distance: CGFloat
            switch direction {
            case .left: valid = dx < 0; distance = abs(dx) + abs(dy) * 1.4
            case .right: valid = dx > 0; distance = abs(dx) + abs(dy) * 1.4
            case .up: valid = dy > 0; distance = abs(dy) + abs(dx) * 1.4
            case .down: valid = dy < 0; distance = abs(dy) + abs(dx) * 1.4
            }
            return valid ? (window, rect, distance) : nil
        }
        guard let target = candidates.min(by: { $0.2 < $1.2 }) else { return }
        move(active.element, to: target.1)
        move(target.0.element, to: activeRect)
    }

    private func scheduleImmediatePoll(after delay: TimeInterval) {
        pendingImmediatePoll?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingImmediatePoll = nil
            self.pollWindows(force: true)
        }
        pendingImmediatePoll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func pollWindows(force: Bool = false) {
        let anyInputEvent = CGEventType(rawValue: .max)!
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEvent)
        if idleSeconds >= 60 {
            // App launch/activation and Space notifications trigger an immediate scan,
            // so this slow fallback only catches unannounced window changes while away.
            let idlePollInterval: TimeInterval = 60
            guard force || Date().timeIntervalSince(lastIdlePollDate) >= idlePollInterval else { return }
            lastIdlePollDate = Date()
        } else {
            lastIdlePollDate = .distantPast
        }
        refreshPermission()
        guard hasAccessibility,
              isEnabled || noPeekActive || cleanSpaceActive || highlight != .none || hoverFocusEnabled else { return }
        let allWindows = collectWindows()
        updateMenuWindows(from: allWindows)
        let windows = allWindows.filter(isTileEligible)
        let ids = Set(windows.map(\.id))
        let active = allWindows.first(where: \.isFocused)?.id
        if hoverFocusEnabled && !cleanSpaceActive && !tabViewActive {
            let pointer = NSEvent.mouseLocation
            let hovered = allWindows.first { appKitFrame(for: $0).contains(pointer) }
            if let hovered, !hovered.isFocused, hovered.id != lastHoverFocusedID {
                lastHoverFocusedID = hovered.id
                NSRunningApplication(processIdentifier: hovered.pid)?.activate(options: [])
                AXUIElementPerformAction(hovered.element, kAXRaiseAction as CFString)
            } else if hovered == nil {
                lastHoverFocusedID = nil
            }
        }
        if cleanSpaceActive {
            if let activeWindow = allWindows.first(where: \.isFocused) {
                guard activeWindow.isMovable else {
                    closeCleanSpace()
                    statusMessage = "Presentation mode ended because the active window cannot be resized."
                    return
                }
                fillCleanSpace(with: activeWindow)
            }
            previousWindowIDs = ids
            if noPeekActive && !tabViewActive { updateNoPeek(windows: allWindows) }
            return
        }
        if tabViewActive { return }
        if noPeekActive { updateNoPeek(windows: allWindows) }
        if !isEnabled {
            if highlight != .none { updateOutlines(windows: allWindows) }
            return
        }
        if !didInitialTile || ids != previousWindowIDs {
            tidyNow()
        } else if active != lastFocusedID || highlight != .none {
            lastFocusedID = active
            updateOutlines(windows: allWindows)
        }
    }

    private func collectWindows() -> [ManagedWindow] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return [] }
        let primaryTop = NSScreen.main?.frame.maxY ?? screens[0].frame.maxY
        let windowSnapshot = onScreenWindowFrames()
        let activeSpaceFrames = windowSnapshot?.framesByPID
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let candidatePIDs = windowSnapshot?.processOrder
            ?? NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        var orderedPIDs = candidatePIDs.filter { $0 != ownPID }
        if let frontmostPID, let index = orderedPIDs.firstIndex(of: frontmostPID), index > 0 {
            orderedPIDs.insert(orderedPIDs.remove(at: index), at: 0)
        }
        // Resolve only processes that currently own visible windows. Enumerating every
        // NSRunningApplication and asking its activation policy forces a LaunchServices
        // IPC round trip for each background app on every poll.
        let running: [(pid: pid_t, app: NSRunningApplication)] = orderedPIDs.compactMap { pid in
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { return nil }
            return (pid, app)
        }
        let visiblePIDs = Set(orderedPIDs)
        for pid in Array(appMetadataCache.keys) where !visiblePIDs.contains(pid) {
            appMetadataCache.removeValue(forKey: pid)
        }
        var output: [ManagedWindow] = []
        for (pid, app) in running {
            let metadata = appMetadata(for: app, pid: pid)
            let appElement = AXUIElementCreateApplication(pid)
            var focusedValue: CFTypeRef?
            AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedValue)
            let focusedElement = focusedValue.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? unsafeBitCast($0, to: AXUIElement.self) : nil }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for window in windows {
                guard stringAttribute(window, kAXRoleAttribute) == kAXWindowRole as String,
                      stringAttribute(window, kAXSubroleAttribute) == kAXStandardWindowSubrole as String else { continue }
                if boolAttribute(window, kAXMinimizedAttribute) || boolAttribute(window, "AXFullScreen") { continue }
                guard let rect = frame(window) else { continue }
                if let activeSpaceFrames,
                   !activeSpaceFrames[pid, default: []].contains(where: { sameWindowFrame($0, rect) }) { continue }
                var canMove = DarwinBoolean(false), canResize = DarwinBoolean(false)
                AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &canMove)
                AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &canResize)
                let appKitY = primaryTop - (rect.origin.y + rect.height)
                let center = CGPoint(x: rect.midX, y: appKitY + rect.height / 2)
                let screenIndex = screens.firstIndex(where: { $0.frame.contains(center) }) ?? nearestScreen(to: center, screens: screens)
                let id = "\(pid):\(CFHash(window))"
                output.append(ManagedWindow(id: id, element: window, pid: pid, bounds: rect, screenIndex: screenIndex,
                                            isFocused: focusedElement.map { CFEqual($0, window) } ?? false,
                                            isMovable: canMove.boolValue && canResize.boolValue,
                                            bundleIdentifier: metadata.bundleIdentifier,
                                            appName: metadata.name,
                                            appIcon: metadata.icon))
            }
        }
        return output
    }

    private func appMetadata(for app: NSRunningApplication, pid: pid_t) -> RunningAppMetadata {
        if let cached = appMetadataCache[pid] { return cached }
        let metadata = RunningAppMetadata(bundleIdentifier: app.bundleIdentifier,
                                          name: app.localizedName,
                                          icon: app.icon)
        appMetadataCache[pid] = metadata
        return metadata
    }

    private func onScreenWindowFrames() -> OnScreenWindowSnapshot? {
        guard let records = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return nil }
        var frames: [pid_t: [CGRect]] = [:]
        var processOrder: [pid_t] = []
        for record in records {
            guard let owner = record[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = record[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0,
                  let bounds = record[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.width > 1, rect.height > 1 else { continue }
            let pid = pid_t(owner.int32Value)
            if frames[pid] == nil { processOrder.append(pid) }
            frames[pid, default: []].append(rect)
        }
        return frames.isEmpty ? nil : OnScreenWindowSnapshot(framesByPID: frames, processOrder: processOrder)
    }

    private func sameWindowFrame(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance: CGFloat = 4
        return abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }

    /// Fits Columns around the minimum widths apps actually accept. When one app
    /// refuses its equal share, the remaining windows are resized into the space
    /// that's left. A second constrained window is detected and the space is
    /// redistributed again before we give up to Grid.
    private func fitColumnFrames(for windows: [ManagedWindow], in rect: CGRect, gap requestedGap: Int) -> [CGRect]? {
        let count = windows.count
        guard count > 1 else { return windows.isEmpty ? [] : [rect] }
        let gap = min(CGFloat(requestedGap), max(0, min(rect.width, rect.height) / CGFloat(max(2, count))))
        let availableWidth = rect.width - gap * CGFloat(count - 1)
        guard availableWidth > 0 else { return nil }

        var minimumWidths = Array(repeating: CGFloat.zero, count: count)
        for _ in 0...count {
            let fixedWidth = minimumWidths.reduce(0, +)
            guard fixedWidth <= availableWidth + 1 else { return nil }

            let flexible = (0..<count).filter { minimumWidths[$0] == 0 }
            let recipients = flexible.isEmpty ? Array(0..<count) : flexible
            let extraPerWindow = max(0, (availableWidth - fixedWidth) / CGFloat(recipients.count))
            var widths = minimumWidths
            for index in recipients { widths[index] += extraPerWindow }

            var x = rect.minX
            let frames = widths.map { width -> CGRect in
                defer { x += width + gap }
                return CGRect(x: x, y: rect.minY, width: width, height: rect.height)
            }

            var discoveredMinimum = false
            for index in windows.indices {
                guard let actual = applyLayoutFrame(to: windows[index].element, frame: frames[index]) else { continue }
                // AX values can differ by a few points due to title-bar rounding.
                if actual.width > widths[index] + 8 {
                    minimumWidths[index] = max(minimumWidths[index], actual.width)
                    discoveredMinimum = true
                }
            }
            if !discoveredMinimum { return frames }
        }
        return nil
    }

    private func applyLayoutFrame(to element: AXUIElement, frame rect: CGRect) -> CGRect? {
        var point = CGPoint(x: rect.minX, y: (NSScreen.main?.frame.maxY ?? 0) - rect.maxY)
        var size = CGSize(width: rect.width, height: rect.height)
        guard let position = AXValueCreate(.cgPoint, &point),
              let dimension = AXValueCreate(.cgSize, &size) else { return nil }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, dimension)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        return frame(element)
    }

    private func tileFrames(in rect: CGRect, count: Int, layout: WindowLayout, gap requestedGap: Int, isTall: Bool) -> [CGRect] {
        guard count > 0 else { return [] }
        if count == 1 { return [rect] }
        let gap = min(CGFloat(requestedGap), max(0, min(rect.width, rect.height) / CGFloat(max(2, count))))
        func splitVertical(_ source: CGRect) -> (CGRect, CGRect) {
            let width = (source.width - gap) / 2
            return (CGRect(x: source.minX, y: source.minY, width: width, height: source.height), CGRect(x: source.minX + width + gap, y: source.minY, width: width, height: source.height))
        }
        func splitHorizontal(_ source: CGRect) -> (CGRect, CGRect) {
            let height = (source.height - gap) / 2
            return (CGRect(x: source.minX, y: source.minY + height + gap, width: source.width, height: height), CGRect(x: source.minX, y: source.minY, width: source.width, height: height))
        }
        if isTall {
            let rows = min(count, 3), height = (rect.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            return (0..<rows).map { index in CGRect(x: rect.minX, y: rect.maxY - height * CGFloat(index + 1) - gap * CGFloat(index), width: rect.width, height: height) }
        }
        if layout == .columns {
            let width = (rect.width - gap * CGFloat(count - 1)) / CGFloat(count)
            return (0..<count).map { CGRect(x: rect.minX + CGFloat($0) * (width + gap), y: rect.minY, width: width, height: rect.height) }
        }
        let (left, right) = splitVertical(rect)
        if count == 2 { return [left, right] }
        let (rightTop, rightBottom) = splitHorizontal(right)
        if count == 3 { return [left, rightTop, rightBottom] }
        let (leftTop, leftBottom) = splitHorizontal(left)
        return [leftTop, rightTop, rightBottom, leftBottom]
    }

    private func move(_ element: AXUIElement, to rect: CGRect) {
        var point = CGPoint(x: rect.minX, y: (NSScreen.main?.frame.maxY ?? 0) - rect.maxY)
        var size = CGSize(width: rect.width, height: rect.height)
        guard let position = AXValueCreate(.cgPoint, &point), let dimension = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, dimension)
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let positionAXValue = unsafeBitCast(positionValue, to: AXValue.self)
        let sizeAXValue = unsafeBitCast(sizeValue, to: AXValue.self)
        guard
              AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size),
              size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              position.x.isFinite, position.y.isFinite else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func nearestScreen(to point: CGPoint, screens: [NSScreen]) -> Int {
        screens.indices.min { lhs, rhs in
            let a = screens[lhs].frame, b = screens[rhs].frame
            return hypot(a.midX - point.x, a.midY - point.y) < hypot(b.midX - point.x, b.midY - point.y)
        } ?? 0
    }

    private func appKitFrame(for window: ManagedWindow) -> CGRect {
        let primaryTop = NSScreen.main?.frame.maxY ?? 0
        return CGRect(x: window.bounds.minX, y: primaryTop - window.bounds.maxY, width: window.bounds.width, height: window.bounds.height)
    }

    private func screenUnderPointer() -> Int {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.firstIndex(where: { $0.frame.contains(point) }) ?? 0
    }

    private func fillCleanSpace(with window: ManagedWindow) {
        guard cleanSpaceActive, window.isMovable, window.screenIndex == cleanScreenIndex,
              NSScreen.screens.indices.contains(window.screenIndex) else { return }
        if cleanSavedFrames[window.id] == nil {
            cleanSavedFrames[window.id] = SavedWindowFrame(element: window.element, frame: appKitFrame(for: window))
        }
        let frame = NSScreen.screens[window.screenIndex].visibleFrame
        move(window.element, to: frame)
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    private func updateNoPeek(windows: [ManagedWindow]? = nil) {
        guard noPeekActive else { return }
        let current = windows ?? collectWindows()
        let focused = current.first(where: \.isFocused)
        noPeekFocusRects.removeAll(keepingCapacity: true)
        if let focused, NSScreen.screens.indices.contains(focused.screenIndex) {
            let screen = NSScreen.screens[focused.screenIndex]
            noPeekFocusRects[focused.screenIndex] = appKitFrame(for: focused)
                .offsetBy(dx: -screen.visibleFrame.minX, dy: -screen.visibleFrame.minY)
        }
        renderNoPeek()
    }

    /// Avoid publishing a new menu model every poll when nothing visible has changed.
    /// Rebuilding the SwiftUI status popover during AppKit hit-testing can crash on macOS 27.
    private func updateMenuWindows(from windows: [ManagedWindow]) {
        let items = windows.map {
            MenuWindowItem(id: $0.id, screenIndex: $0.screenIndex, appName: $0.appName ?? "App",
                           icon: $0.appIcon, bundleIdentifier: $0.bundleIdentifier, isFocused: $0.isFocused)
        }
        guard items.count != menuWindows.count || zip(items, menuWindows).contains(where: { lhs, rhs in
            lhs.id != rhs.id || lhs.screenIndex != rhs.screenIndex || lhs.appName != rhs.appName ||
                lhs.bundleIdentifier != rhs.bundleIdentifier || lhs.isFocused != rhs.isFocused
        }) else { return }
        menuWindows = items
    }

    /// Repaint the existing dimming panels without querying Accessibility or the window server.
    /// This is important for the menu slider, which can send many updates per second.
    private func renderNoPeek() {
        guard noPeekActive else { return }
        let screens = NSScreen.screens
        for staleIndex in Array(noPeekPanels.keys).filter({ !screens.indices.contains($0) }) {
            noPeekPanels.removeValue(forKey: staleIndex)?.close()
        }
        for (index, screen) in screens.enumerated() {
            let panel = noPeekPanels[index] ?? {
                let value = NoPeekPanel()
                noPeekPanels[index] = value
                return value
            }()
            let hole = noPeekFocusRects[index]
            panel.show(on: screen, focusRect: hole, dimAmount: CGFloat(noPeekDimAmount) / 100, blur: noPeekBlurEnabled)
        }
    }

    private func updateOutlines(windows: [ManagedWindow]? = nil) {
        guard highlight != .none, hasAccessibility else { clearOutlines(); return }
        let current = windows ?? collectWindows()
        let focused = current.first(where: \.isFocused)?.id
        lastFocusedID = focused
        let wanted = current.filter { highlight == .allBorders || $0.id == focused }
        let wantedIDs = Set(wanted.map(\.id))
        for id in overlays.keys where !wantedIDs.contains(id) { overlays[id]?.close(); overlays.removeValue(forKey: id) }
        for window in wanted {
            let primaryTop = NSScreen.main?.frame.maxY ?? 0
            let appKitY = primaryTop - window.bounds.maxY
            let rect = CGRect(x: window.bounds.minX, y: appKitY, width: window.bounds.width, height: window.bounds.height)
            if let overlay = overlays[window.id] { overlay.show(frame: rect, color: Self.accents[accentName] ?? .systemBlue, glow: highlight == .glow) }
            else {
                let overlay = WindowOutline()
                overlays[window.id] = overlay
                overlay.show(frame: rect, color: Self.accents[accentName] ?? .systemBlue, glow: highlight == .glow)
            }
        }
    }

    private func clearOutlines() { overlays.values.forEach { $0.close() }; overlays.removeAll() }

    private func isTileEligible(_ window: ManagedWindow) -> Bool {
        window.isMovable && !(window.bundleIdentifier.map(excludedApps.contains) ?? false)
    }

    private func layoutSettings(for screen: NSScreen, index: Int) -> ScreenLayoutSettings {
        perScreenSettings[displayID(screen, index: index)] ?? ScreenLayoutSettings(layout: layout, windowLimit: windowLimit, gap: gap)
    }

    private func displayID(_ screen: NSScreen, index: Int) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return "display-index-\(index)"
    }
}

private extension Int {
    func nonZero(or fallback: Int) -> Int { self == 0 ? fallback : self }
}

private extension NSColor {
    convenience init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
                  green: CGFloat((value >> 8) & 0xff) / 255,
                  blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }
}

private extension Collection where Index == Int {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

@MainActor
private final class WindowOutline {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let outlineView = NSView()
    private var lastFrame: CGRect?
    private var lastColor: NSColor?
    private var lastGlow: Bool?

    init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = false
        outlineView.wantsLayer = true
        panel.contentView = outlineView
    }

    func show(frame: CGRect, color: NSColor, glow: Bool) {
        guard frame.width > 4, frame.height > 4 else { close(); return }
        let inset = frame.insetBy(dx: 2, dy: 2)
        if lastFrame != inset {
            panel.setFrame(inset, display: true)
            outlineView.frame = CGRect(origin: .zero, size: inset.size)
            lastFrame = inset
        }
        if lastColor?.isEqual(color) != true || lastGlow != glow {
            outlineView.layer?.borderWidth = glow ? 0 : 3
            outlineView.layer?.borderColor = color.cgColor
            outlineView.layer?.cornerRadius = 9
            outlineView.layer?.backgroundColor = glow ? color.withAlphaComponent(0.10).cgColor : NSColor.clear.cgColor
            outlineView.layer?.shadowColor = glow ? color.cgColor : NSColor.clear.cgColor
            outlineView.layer?.shadowOpacity = glow ? 0.75 : 0
            outlineView.layer?.shadowRadius = glow ? 12 : 0
            lastColor = color
            lastGlow = glow
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func close() { panel.orderOut(nil) }
}
