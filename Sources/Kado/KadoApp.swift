import AppKit
import SwiftUI

@MainActor
@main
struct KadoApp: App {
    @NSApplicationDelegateAdaptor(KadoAppDelegate.self) private var appDelegate
    @StateObject private var manager = WindowManager.shared

    var body: some Scene {
        Settings {
            SettingsPanel(manager: manager)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
private final class KadoAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = Self.statusMark()
            button.image = image
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Kado window manager")
            button.setAccessibilityIdentifier("KadoStatusItem")
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item

        let controller = NSHostingController(rootView: MenuBarPanel(manager: WindowManager.shared))
        controller.view.appearance = NSAppearance(named: .aqua)
        controller.preferredContentSize = NSSize(width: 320, height: 720)
        popover.contentSize = controller.preferredContentSize
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = controller
    }

    private static func statusMark() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: CGRect(x: 2, y: 2, width: 5, height: 14), xRadius: 1.5, yRadius: 1.5).fill()
            NSBezierPath(roundedRect: CGRect(x: 9, y: 9, width: 7, height: 7), xRadius: 1.5, yRadius: 1.5).fill()
            NSBezierPath(roundedRect: CGRect(x: 9, y: 2, width: 7, height: 5), xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            WindowManager.shared.refreshMenuWindows()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        popover.close()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}

struct MenuBarPanel: View {
    @ObservedObject var manager: WindowManager

    private var screenIndex: Int { manager.menuScreenIndex }
    private var screenWindows: [MenuWindowItem] {
        manager.menuWindows.filter { $0.screenIndex == screenIndex }
            .sorted { lhs, rhs in lhs.isFocused && !rhs.isFocused }
    }
    private var activeWindow: MenuWindowItem? {
        screenWindows.first(where: \.isFocused) ?? screenWindows.first
    }
    private var columnCapacity: Int { manager.columnCapacity(for: screenIndex) }
    private var screenLayout: WindowLayout { manager.layoutForScreen(at: screenIndex) }
    private var screenWindowLimit: Int { manager.windowLimitForScreen(at: screenIndex) }
    private var cardWidth: CGFloat {
        let count = min(max(screenWindows.count, 1), 3)
        return (296 - CGFloat(count - 1) * 7) / CGFloat(count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, 25)

            if !manager.hasAccessibility {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield").foregroundStyle(.orange)
                    Text("Kado needs Accessibility access.").font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 2)
                    Button("Open Settings") { manager.requestAccessibility() }
                        .font(.system(size: 10, weight: .semibold)).buttonStyle(.borderedProminent)
                }
                .padding(9)
                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
                .padding(.bottom, 10)
            }

            windowGallery

            Text("Windows on this screen")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.65))
                .padding(.top, 20).padding(.bottom, 11)

            HStack(spacing: 3) {
                ForEach(WindowLayout.allCases) { layout in
                    LayoutChoice(layout: layout, selected: screenLayout == layout) {
                        manager.setLayout(layout, forScreenAt: screenIndex)
                    }
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.075), in: RoundedRectangle(cornerRadius: 9))

            HStack(spacing: 4) {
                ForEach(1...4, id: \.self) { count in
                    WindowCountButton(count: count, selected: screenWindowLimit == count,
                                      disabled: screenLayout == .columns && count > columnCapacity) {
                        manager.setWindowLimit(count, forScreenAt: screenIndex)
                    }
                }
            }
            .padding(.top, 7)

            if screenLayout == .columns && columnCapacity < 4 {
                Text("This screen fits \(columnCapacity) columns. Pick Grid for four.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .padding(.top, 5)
            }

            HStack(spacing: 5) {
                QuickActionButton(title: "Retile", symbol: "arrow.clockwise", selected: false, action: manager.tidyNow)
                QuickActionButton(title: "Borders", symbol: "rectangle.inset.filled", selected: manager.highlight != .none) {
                    manager.setHighlight(manager.highlight == .none ? .activeBorder : .none)
                }
                QuickActionButton(title: "Hover focus", symbol: "cursorarrow.motionlines", selected: manager.hoverFocusEnabled) {
                    manager.setHoverFocusEnabled(!manager.hoverFocusEnabled)
                }
            }
            .padding(.top, 19).padding(.bottom, 10)

            Divider().padding(.bottom, 4)
            ModeRow(symbol: "rectangle.expand.vertical", title: "Presentation", shortcut: "⌃⌥P", isOn: manager.cleanSpaceActive) {
                manager.toggleCleanSpace()
            }
            NoPeekModeRow(isOn: manager.noPeekActive, dimAmount: manager.noPeekDimAmount, action: manager.toggleNoPeek) {
                manager.setNoPeekDimAmount($0)
            }

            if let activeWindow {
                HStack(spacing: 7) {
                    appIcon(activeWindow.icon, name: activeWindow.appName, size: 19)
                    Toggle(isOn: Binding(
                        get: { activeWindow.bundleIdentifier.map { !manager.excludedApps.contains($0) } ?? true },
                        set: { value in
                            if let bundleID = activeWindow.bundleIdentifier { manager.setAppExcluded(bundleID, excluded: !value) }
                        }
                    )) {
                        Text("Tile \(activeWindow.appName)").font(.system(size: 11, weight: .medium)).lineLimit(1)
                    }
                    .toggleStyle(.switch).controlSize(.mini).tint(.blue)
                }
                .frame(height: 40)
                .padding(.top, 8)
            }

            Divider().padding(.top, 4)
            SettingsLink {
                FooterRow(symbol: "slider.horizontal.3", title: "Kado settings", trailing: "⌘,")
            }
            .buttonStyle(.plain).keyboardShortcut(",")
            .simultaneousGesture(TapGesture().onEnded {
                UserDefaults.standard.set(SettingsSection.focus.rawValue, forKey: "settingsRequestedSection")
            })
            SettingsLink {
                FooterRow(symbol: "command", title: "Shortcut list", trailing: "›")
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                UserDefaults.standard.set(SettingsSection.shortcuts.rawValue, forKey: "settingsRequestedSection")
            })
            Button { manager.quitKado() } label: {
                FooterRow(symbol: "power", title: "Quit Kado", trailing: "")
                    .foregroundStyle(Color.black.opacity(0.48))
            }
            .buttonStyle(.plain).keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: 320, height: 720, alignment: .topLeading)
        .background(Color(red: 0.965, green: 0.963, blue: 0.975))
        .tint(.blue)
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .onAppear { manager.refreshMenuWindows() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            KadoMark(style: manager.appIconStyle, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kado").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 5) {
                    Circle().fill(manager.isEnabled ? Color.green : Color.gray.opacity(0.65)).frame(width: 6, height: 6)
                    Text(manager.isEnabled ? "Tiling \(screenWindows.count) windows" : "Automatic tiling is paused")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Toggle("Automatic tiling", isOn: Binding(get: { manager.isEnabled }, set: manager.setEnabled))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(.blue)
        }
        .frame(height: 34)
    }

    private var windowGallery: some View {
        Group {
            if screenWindows.isEmpty {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.65))
                    .overlay(Text(manager.hasAccessibility ? "No windows on this screen" : "Windows will appear here")
                        .font(.system(size: 11)).foregroundStyle(.secondary))
                    .frame(height: 152)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(screenWindows) { item in
                            WindowPreviewCard(item: item, selected: item.isFocused, width: cardWidth) {
                                manager.focusMenuWindow(item.id)
                            }
                        }
                    }
                }
                .frame(height: 152)
            }
        }
    }

    @ViewBuilder private func appIcon(_ icon: NSImage?, name: String, size: CGFloat) -> some View {
        if let icon {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            Image(systemName: "app.fill").resizable().scaledToFit().frame(width: size, height: size)
                .foregroundStyle(.secondary).accessibilityLabel(name)
        }
    }
}

private struct WindowPreviewCard: View {
    let item: MenuWindowItem
    let selected: Bool
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                if let icon = item.icon {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 19, height: 19)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: "app.fill").font(.system(size: 18)).foregroundStyle(.secondary)
                }
                Text(item.appName).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(width: width, height: 152)
            .background(selected ? Color.blue.opacity(0.09) : Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.blue : Color.black.opacity(0.18), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}

private struct LayoutChoice: View {
    let layout: WindowLayout
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: layout == .grid ? "rectangle.split.2x1" : "rectangle.split.3x1")
                    .font(.system(size: 11, weight: .semibold))
                Text(layout.title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.black.opacity(0.73))
            .frame(maxWidth: .infinity).frame(height: 23)
            .background(selected ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

private struct WindowCountButton: View {
    let count: Int
    let selected: Bool
    let disabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(0..<count, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(selected ? Color.blue : Color.black.opacity(0.18))
                    }
                }
                .frame(width: 41, height: 21)
                Text("\(count)").font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selected ? Color.blue : Color.black.opacity(0.68))
            .frame(maxWidth: .infinity).frame(height: 60)
            .background(selected ? Color.blue.opacity(0.10) : Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.blue : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain).disabled(disabled)
        .opacity(disabled ? 0.38 : 1)
        .accessibilityLabel("\(count) windows")
    }
}

private struct QuickActionButton: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.blue : Color.black.opacity(0.78))
            .frame(maxWidth: .infinity).frame(height: 54)
            .background(selected ? Color.blue.opacity(0.10) : Color.black.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}

private struct ModeRow: View {
    let symbol: String
    let title: String
    let shortcut: String
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 16)
                .foregroundStyle(Color.black.opacity(0.63))
            Text(title).font(.system(size: 11, weight: .medium))
            Text(shortcut).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Toggle(title, isOn: Binding(get: { isOn }, set: { _ in action() }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(.blue)
        }
        .frame(height: 34)
    }
}

private struct NoPeekModeRow: View {
    let isOn: Bool
    let dimAmount: Int
    let action: () -> Void
    let setDimAmount: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.lefthalf.filled").font(.system(size: 12, weight: .medium)).frame(width: 16)
                .foregroundStyle(Color.black.opacity(0.63))
            Text("Dim surroundings").font(.system(size: 11, weight: .medium)).lineLimit(1)
            if isOn {
                Slider(value: Binding(get: { Double(dimAmount) }, set: { setDimAmount(Int($0)) }), in: 10...90, step: 5)
                    .labelsHidden().controlSize(.mini).tint(.blue).frame(width: 76)
                Text("\(dimAmount)%").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            } else {
                Text("⌃⌥D").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
            }
            Toggle("Dim surroundings", isOn: Binding(get: { isOn }, set: { _ in action() }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(.blue)
        }
        .frame(height: 34)
    }
}

private struct FooterRow: View {
    let symbol: String
    let title: String
    let trailing: String
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 13)
            Text(title).font(.system(size: 11, weight: .medium))
            Spacer()
            Text(trailing).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .foregroundStyle(Color.black.opacity(0.80))
        .frame(height: 36)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case focus = "Arrangement"
    case shortcuts = "Shortcuts"
    case noPeek = "Screen dimming"
    case cleanSpace = "Presentation"
    case tabView = "Window switcher"
    case displays = "Displays"
    case layout = "Display profiles"
    case privacy = "Privacy"
    case apps = "App rules"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .focus: "rectangle.split.3x1"
        case .shortcuts: "command"
        case .noPeek: "eye.slash"
        case .cleanSpace: "rectangle.expand.vertical"
        case .tabView: "rectangle.stack"
        case .displays: "display.2"
        case .layout: "square.grid.2x2"
        case .privacy: "hand.raised"
        case .apps: "square.grid.3x3"
        }
    }
    var subtitle: String {
        switch self {
        case .focus: "Choose a layout and how Kado places new windows."
        case .shortcuts: "Keyboard controls available from any app."
        case .noPeek: "Dim or soften the windows around the one you use."
        case .cleanSpace: "Prepare one display for a clear presentation."
        case .tabView: "Preview open windows and move between them."
        case .displays: "See the screens Kado can arrange."
        case .layout: "Set a separate arrangement for each display."
        case .privacy: "What Kado reads and keeps on this Mac."
        case .apps: "Choose which running apps Kado can arrange."
        }
    }
}

struct SettingsPanel: View {
    @ObservedObject var manager: WindowManager
    @State private var selectedSection: SettingsSection = .focus
    @State private var selectedDisplayID = ""
    @State private var appSearch = ""
    @AppStorage("settingsRequestedSection") private var settingsRequestedSection = SettingsSection.focus.rawValue

    private let columns = [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)]
    private let sidebarWidth: CGFloat = 208
    private var selectedDisplay: DisplayPreference? {
        manager.displayPreferences.first(where: { $0.id == selectedDisplayID }) ?? manager.displayPreferences.first
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: sidebarWidth)
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 30)
                    .padding(.vertical, 22)
                Divider().overlay(Color.black.opacity(0.04))
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 16) {
                        if !manager.hasAccessibility { permissionNotice }
                        page
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(28)
                }
            }
            .background(Color(red: 0.95, green: 0.96, blue: 0.975))
        }
        .frame(minWidth: 900, idealWidth: 1040, minHeight: 650, idealHeight: 760)
        .preferredColorScheme(.light)
        .onAppear {
            manager.refreshPermission()
            if selectedDisplayID.isEmpty { selectedDisplayID = manager.displayPreferences.first?.id ?? "" }
            selectRequestedSection()
        }
        .onChange(of: settingsRequestedSection) { _, _ in selectRequestedSection() }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: selectedSection.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.13, green: 0.39, blue: 0.88))
                .frame(width: 38, height: 38)
                .background(Color.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedSection.rawValue)
                    .font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(Color(red: 0.10, green: 0.15, blue: 0.23))
                Text(selectedSection.subtitle)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.black.opacity(0.48))
            }
            Spacer()
            if selectedSection == .focus {
                HStack(spacing: 8) {
                    Circle().fill(manager.isEnabled ? Color.green : Color.gray).frame(width: 7, height: 7)
                    Text(manager.isEnabled ? "Tiling active" : "Tiling paused")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.white, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                KadoMark(style: manager.appIconStyle, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kado").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text("WINDOW MANAGER").font(.system(size: 8, weight: .bold)).tracking(1.1).foregroundStyle(.white.opacity(0.46))
                }
            }
            .padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 22)

            Rectangle().fill(.white.opacity(0.09)).frame(height: 1).padding(.horizontal, 16).padding(.bottom, 20)
            sidebarGroup("WORKSPACE", sections: [.focus, .displays, .layout])
            sidebarGroup("MODES", sections: [.noPeek, .cleanSpace, .tabView])
            sidebarGroup("PREFERENCES", sections: [.apps, .shortcuts, .privacy])
            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Circle().fill(manager.isEnabled ? Color.green : Color.white.opacity(0.36)).frame(width: 7, height: 7)
                Text(manager.isEnabled ? "Window tiling is on" : "Window tiling is paused")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 14).padding(.bottom, 10)

            SettingsLink {
                Label("System Settings", systemImage: "gearshape")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.60))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).frame(height: 34)
            }
            .buttonStyle(.plain).padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.105, green: 0.145, blue: 0.215))
    }

    private func sidebarGroup(_ title: String, sections: [SettingsSection]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(1.15)
                .foregroundStyle(.white.opacity(0.38)).padding(.horizontal, 15).padding(.bottom, 5)
            ForEach(sections) { section in
                Button { selectedSection = section } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.symbol).font(.system(size: 13, weight: .medium)).frame(width: 18)
                        Text(section.rawValue).font(.system(size: 11, weight: selectedSection == section ? .semibold : .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selectedSection == section ? .white : .white.opacity(0.64))
                    .padding(.horizontal, 11).frame(height: 34)
                    .background(selectedSection == section ? Color.blue.opacity(0.78) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).padding(.horizontal, 9)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
            }
        }
        .padding(.bottom, 18)
    }

    @ViewBuilder private var page: some View {
        switch selectedSection {
        case .focus: focusPage
        case .shortcuts: shortcutsPage
        case .noPeek: noPeekPage
        case .cleanSpace: cleanSpacePage
        case .tabView: tabViewPage
        case .displays: displaysPage
        case .layout: layoutPage
        case .privacy: privacyPage
        case .apps: appsPage
        }
    }

    private var permissionNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(.orange).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Allow Kado to position and resize windows.").font(.system(size: 12, weight: .semibold))
                Text(manager.accessibilityPermissionHelp).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Open Settings") { manager.requestAccessibility() }.buttonStyle(.bordered)
        }
        .padding(12)
        .frame(maxWidth: 640, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var focusPage: some View {
        VStack(spacing: 13) {
            KadoCard {
                VStack(alignment: .leading, spacing: 17) {
                    PageHeading("Window arrangement", subtitle: "Set a default pattern. Kado adjusts column widths when an app has a minimum window size.")
                    Picker("Default layout", selection: Binding(get: { manager.layout }, set: { manager.setLayout($0) })) {
                        ForEach(WindowLayout.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Window limit").font(.system(size: 12, weight: .semibold))
                            Text("Maximum tiled windows on each display")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Window count", selection: Binding(get: { manager.windowLimit }, set: { manager.setWindowLimit($0) })) {
                            ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented).frame(width: 190)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Window spacing").font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text("\(manager.gap) pt").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(get: { Double(manager.gap) }, set: { manager.setGap(Int($0)) }), in: 0...24, step: 1).tint(.blue)
                    }
                    HStack {
                        Text("Changes apply as windows open.").font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Arrange now") { manager.tidyNow() }.buttonStyle(.borderedProminent).tint(.blue)
                    }
                }
            }

            KadoCard {
                VStack(alignment: .leading, spacing: 16) {
                    PageHeading("Window markers", subtitle: "Use outlines to spot window boundaries. The accent also colors the Kado mark in the panel.")
                    VStack(alignment: .leading, spacing: 9) {
                        SectionLabel("Outline style")
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(HighlightStyle.allCases) { style in
                                Button { manager.setHighlight(style) } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: style == manager.highlight ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 13)).foregroundStyle(manager.highlight == style ? Color.blue : Color.secondary)
                                        Text(style.title).font(.system(size: 11, weight: .medium))
                                        Spacer(minLength: 0)
                                    }
                                    .foregroundStyle(Color.black.opacity(0.74))
                                    .padding(.horizontal, 10).frame(height: 36)
                                    .background(manager.highlight == style ? Color.blue.opacity(0.08) : Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 9))
                                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(manager.highlight == style ? Color.blue.opacity(0.55) : Color.black.opacity(0.07), lineWidth: 1))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        SectionLabel("Accent")
                        HStack(spacing: 10) {
                            ForEach(Array(WindowManager.accents.keys.sorted(by: { accentOrder($0) < accentOrder($1) })), id: \.self) { name in
                                let color = Color(nsColor: WindowManager.accents[name] ?? .systemBlue)
                                Button { manager.setAccent(name) } label: {
                                    Circle().fill(color).frame(width: 25, height: 25).padding(3)
                                        .overlay(Circle().stroke(manager.accentName == name ? Color.blue : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain).accessibilityLabel("\(name) accent color")
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        SectionLabel("Panel mark · \(manager.appIconStyle.title)")
                        HStack(spacing: 8) {
                            ForEach(AppIconStyle.allCases) { style in
                                Button { manager.setAppIconStyle(style) } label: {
                                    KadoMark(style: style, size: 34)
                                        .frame(width: 40, height: 40)
                                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(manager.appIconStyle == style ? Color.blue : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain).accessibilityLabel("\(style.title) panel mark")
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private var noPeekPage: some View {
        VStack(spacing: 13) {
            KadoCard {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeading("Screen dimming", subtitle: "Keep attention on the front window. Other windows and the desktop fade across your displays, with optional blur for shared screens.")
                    Toggle(isOn: Binding(get: { manager.noPeekActive }, set: { if $0 != manager.noPeekActive { manager.toggleNoPeek() } })) {
                        Label("Dim background windows", systemImage: "eye.slash").font(.system(size: 13, weight: .semibold))
                    }.toggleStyle(.switch).tint(.blue)
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            SectionLabel("Dim amount")
                            Spacer()
                            Text("\(manager.noPeekDimAmount)%").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(get: { Double(manager.noPeekDimAmount) }, set: { manager.setNoPeekDimAmount(Int($0)) }), in: 10...90, step: 5).tint(.blue)
                    }
                    Toggle(isOn: Binding(get: { manager.noPeekBlurEnabled }, set: manager.setNoPeekBlurEnabled)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Blur background windows").font(.system(size: 11, weight: .semibold))
                            Text("Makes their contents harder to read while you share your screen.").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.switch).tint(.blue)
                    ShortcutCapsule("⌃⌥D", enabled: manager.keyboardShortcutsEnabled)
                }
            }
        }
    }

    private var cleanSpacePage: some View {
        KadoCard {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading("Presentation", subtitle: "Expand the focused window to one display and cover the unused area with a simple backdrop.")
                Toggle(isOn: Binding(get: { manager.cleanSpaceActive }, set: { if $0 != manager.cleanSpaceActive { manager.toggleCleanSpace() } })) {
                    Label("Use presentation view", systemImage: "rectangle.expand.vertical").font(.system(size: 13, weight: .semibold))
                }.toggleStyle(.switch).tint(.blue)
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel("Backdrop color")
                    HStack(spacing: 12) {
                        ForEach(CleanBackground.allCases) { background in
                            Button { manager.setCleanBackground(background) } label: {
                                Circle().fill(Color(nsColor: background.color)).frame(width: 34, height: 34)
                                    .padding(4).overlay(Circle().stroke(manager.cleanBackground == background ? Color.blue : .clear, lineWidth: 3))
                            }.buttonStyle(.plain).accessibilityLabel("\(background.title) backdrop")
                        }
                    }
                }
                Text("This affects only the focused display. Kado remembers the original window positions and restores them when presentation view ends, the Mac sleeps, or you quit the app.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ShortcutCapsule("⌃⌥P", enabled: manager.keyboardShortcutsEnabled)
            }
        }
    }

    private var tabViewPage: some View {
        KadoCard {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading("Window switcher", subtitle: "Browse the open windows on your Mac and select one from a compact preview. Kado uses window bounds, not screenshots.")
                HStack {
                    Button { manager.toggleTabView() } label: { Label("Show window switcher", systemImage: "rectangle.stack") }
                        .buttonStyle(.borderedProminent).tint(.blue)
                    Spacer()
                    ShortcutCapsule("⌥Tab", enabled: manager.keyboardShortcutsEnabled)
                }
                Text("Hold Option and press Tab to cycle. Release Option to switch, or use the arrow keys and Return. Shift–Option–Tab cycles backwards. Escape closes the view.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var displaysPage: some View {
        VStack(spacing: 12) {
            KadoCard {
                VStack(alignment: .leading, spacing: 15) {
                    PageHeading("Connected displays", subtitle: "Review each monitor and jump to its layout profile.")
                    ForEach(manager.displayPreferences) { display in
                        HStack(spacing: 12) {
                            Image(systemName: "display").font(.system(size: 20)).foregroundStyle(.blue).frame(width: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(display.name).font(.system(size: 14, weight: .semibold))
                                Text("\(Int(display.frame.width)) × \(Int(display.frame.height)) · \(display.layout.title) · \(display.windowLimit)-window limit")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Configure") { selectedDisplayID = display.id; selectedSection = .layout }
                                .buttonStyle(.bordered)
                        }
                        .padding(12)
                        .background(Color(red: 0.96, green: 0.96, blue: 0.96), in: RoundedRectangle(cornerRadius: 15))
                    }
                    if manager.displayPreferences.isEmpty {
                        Text("No displays found.").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var layoutPage: some View {
        KadoCard {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading("Display profile", subtitle: "Choose a pattern, window cap, and spacing for the selected monitor.")
                Picker("Display", selection: $selectedDisplayID) {
                    ForEach(manager.displayPreferences) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)
                if let display = selectedDisplay {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Arrangement")
                        Picker("Layout", selection: Binding(get: { display.layout }, set: { manager.setScreenLayout($0, id: display.id) })) {
                            ForEach(WindowLayout.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    HStack {
                        Text("Windows on this screen").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("Window limit", selection: Binding(get: { display.windowLimit }, set: { manager.setScreenWindowLimit($0, id: display.id) })) {
                            ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                        }.pickerStyle(.segmented).frame(width: 180)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        SectionLabel("Space · \(display.gap) pt")
                        Slider(value: Binding(get: { Double(display.gap) }, set: { manager.setScreenGap(Int($0), id: display.id) }), in: 0...24, step: 1).tint(.blue)
                    }
                } else {
                    Text("Connect a display to configure its layout.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var privacyPage: some View {
        KadoCard {
            VStack(alignment: .leading, spacing: 17) {
                PageHeading("Local by default", subtitle: "Kado needs window geometry to place windows. It does not inspect app content or collect activity data.")
                PrivacyFact("rectangle.dashed", title: "Window measurements", detail: "Position and size are used for layout and previews. Window titles and document contents are not read.")
                PrivacyFact("cursorarrow", title: "Pointer checks", detail: "During a drag swap, pointer coordinates identify which two windows to exchange. The coordinates are not recorded.")
                PrivacyFact("keyboard", title: "Shortcut handling", detail: "Kado registers its shortcut combinations only; it does not capture general typing.")
                PrivacyFact("internaldrive", title: "Stored on this Mac", detail: "Preferences remain in macOS local storage. Kado does not send usage analytics.")
            }
        }
    }

    private var shortcutsPage: some View {
        KadoCard {
            VStack(alignment: .leading, spacing: 16) {
                PageHeading("Keyboard controls", subtitle: "Use these combinations while another app is frontmost. Disable global shortcuts below if they conflict with your workflow.")
                Toggle(isOn: Binding(get: { manager.keyboardShortcutsEnabled }, set: manager.setKeyboardShortcutsEnabled)) {
                    Text("Enable keyboard shortcuts").font(.system(size: 13, weight: .medium))
                }.toggleStyle(.switch).tint(.blue)
                VStack(spacing: 0) {
                    ShortcutRow("⌃⌥⌘1–4", detail: "Arrange up to four windows")
                    ShortcutRow("⌃⌥← → ↑ ↓", detail: "Swap the focused window")
                    ShortcutRow("⌥Tab / ⇧⌥Tab", detail: "Open the switcher or move through it")
                    ShortcutRow("⌃⌥P", detail: "Toggle presentation view")
                    ShortcutRow("⌃⌥D", detail: "Toggle screen dimming")
                }
            }
        }
    }

    private var appsPage: some View {
        VStack(spacing: 12) {
            KadoCard {
                VStack(alignment: .leading, spacing: 14) {
                    PageHeading("App rules", subtitle: "Exclude a running app when its windows should keep their current positions.")
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Filter apps", text: $appSearch).textFieldStyle(.plain)
                    }
                    .padding(10).background(Color(red: 0.96, green: 0.96, blue: 0.96), in: RoundedRectangle(cornerRadius: 12))
                    ForEach(manager.appPreferences.filter { appSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(appSearch) }) { app in
                        HStack(spacing: 10) {
                            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6)) }
                            else { Image(systemName: "app").frame(width: 28, height: 28) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name).font(.system(size: 13, weight: .medium))
                                Text(app.id).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                            }
                            Spacer()
                            Toggle("Exclude from tiling", isOn: Binding(get: { app.excluded }, set: { manager.setAppExcluded(app.id, excluded: $0) }))
                                .labelsHidden().toggleStyle(.switch).tint(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                    if manager.appPreferences.isEmpty { Text("Open an app to add it to this list.").font(.system(size: 12)).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func accentOrder(_ name: String) -> Int {
        ["Blue", "Purple", "Pink", "Orange", "Green", "Graphite"].firstIndex(of: name) ?? 99
    }

    private func selectRequestedSection() {
        if let section = SettingsSection(rawValue: settingsRequestedSection) { selectedSection = section }
    }
}

private struct ShortcutRow: View {
    let shortcut: String
    let detail: String
    init(_ shortcut: String, detail: String) { self.shortcut = shortcut; self.detail = detail }
    var body: some View {
        HStack {
            Text(detail).font(.system(size: 12, weight: .medium))
            Spacer()
            Text(shortcut).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
        .frame(height: 38)
        Divider()
    }
}

private struct KadoCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(21)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.black.opacity(0.075), lineWidth: 1))
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.48))
    }
}

private struct PageHeading: View {
    let title: String
    let subtitle: String
    init(_ title: String, subtitle: String) { self.title = title; self.subtitle = subtitle }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(Color.black.opacity(0.82))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Color.black.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ShortcutCapsule: View {
    let shortcut: String
    let enabled: Bool
    init(_ shortcut: String, enabled: Bool) { self.shortcut = shortcut; self.enabled = enabled }
    var body: some View {
        HStack(spacing: 6) {
            Text(shortcut).font(.system(size: 12, weight: .semibold, design: .rounded).monospaced())
            if !enabled { Text("Off").font(.system(size: 10, weight: .medium)) }
        }
        .foregroundStyle(enabled ? Color.black.opacity(0.62) : Color.secondary)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Color.black.opacity(0.05), in: Capsule())
    }
}

private struct PrivacyFact: View {
    let symbol: String
    let title: String
    let detail: String
    init(_ symbol: String, title: String, detail: String) { self.symbol = symbol; self.title = title; self.detail = detail }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.blue).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct KadoMark: View {
    let style: AppIconStyle
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(Color(nsColor: style.background))
            HStack(spacing: size * 0.07) {
                tile(0).frame(width: size * 0.24, height: size * 0.57)
                VStack(spacing: size * 0.07) {
                    tile(1)
                    tile(2)
                }
                .frame(width: size * 0.24, height: size * 0.57)
            }
            .frame(width: size * 0.55, height: size * 0.57)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
    private func tile(_ index: Int) -> some View {
        RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
            .fill(Color(nsColor: style.tiles[index]))
    }
}
