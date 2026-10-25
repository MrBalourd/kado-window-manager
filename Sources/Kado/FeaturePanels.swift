import AppKit
import SwiftUI

@MainActor
final class TabPickerPanel: NSPanel {
    private weak var manager: WindowManager?
    var selectedID: String? { didSet { contentView = makeContent() } }

    init(manager: WindowManager) {
        self.manager = manager
        let screenFrame = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let frame = screenFrame.isNull || screenFrame.isEmpty ? CGRect(x: 0, y: 0, width: 900, height: 600) : screenFrame
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        worksWhenModal = true
        contentView = makeContent()
    }

    private func makeContent() -> NSView {
        let view = NSHostingView(rootView: TabViewOverlay(manager: manager, selectedID: selectedID))
        view.frame = frame
        return view
    }

    func show() {
        selectedID = manager?.tabViewItems.first?.id
        orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        makeKey()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: manager?.closeTabView() // Escape
        case 36, 76: manager?.selectCurrentTabWindow() // Return / keypad Enter
        case 123, 126: manager?.moveTabSelection(-1)
        case 124, 125: manager?.moveTabSelection(1)
        default: super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        if !event.modifierFlags.contains(.option), manager?.tabViewActive == true {
            manager?.selectCurrentTabWindow()
        }
    }

    override func close() {
        orderOut(nil)
        manager?.tabPanelDidClose()
    }
}

private struct TabViewOverlay: View {
    weak var manager: WindowManager?
    let selectedID: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
                .onTapGesture { manager?.closeTabView() }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Window switcher", systemImage: "rectangle.stack")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("Release ⌥ to switch · Esc to close")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.68))
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(groupedScreens, id: \.screen) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.title.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .tracking(1.4).foregroundStyle(.white.opacity(0.58))
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                                    ForEach(group.items) { item in
                                        Button { manager?.selectTabWindow(item.id) } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .windowBackgroundColor))
                                                    WindowThumbnail(item: item)
                                                }
                                                .frame(height: 105).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                                                HStack(spacing: 7) {
                                                    if let icon = item.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(item.appName).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                                    Text("Display \(item.screenIndex + 1) · Window layout").font(.system(size: 10)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                                                    }
                                                    Spacer(minLength: 0)
                                                }
                                            }
                                            .padding(8)
                                            .background(selectedID == item.id ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedID == item.id ? Color.white.opacity(0.9) : Color.white.opacity(0.12), lineWidth: selectedID == item.id ? 2 : 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 740, maxHeight: 620)
            .background(.ultraThinMaterial.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 14)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var groupedScreens: [(screen: Int, title: String, items: [TabWindowItem])] {
        guard let items = manager?.tabViewItems else { return [] }
        return Dictionary(grouping: items, by: \.screenIndex).keys.sorted().map { index in
            (index, "Display \(index + 1)", items.filter { $0.screenIndex == index })
        }
    }
}

private struct WindowThumbnail: View {
    let item: TabWindowItem
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color.white.opacity(0.16), Color.black.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.95))
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 4) {
                            Circle().fill(.red.opacity(0.75)).frame(width: 5, height: 5)
                            Circle().fill(.yellow.opacity(0.75)).frame(width: 5, height: 5)
                            Circle().fill(.green.opacity(0.75)).frame(width: 5, height: 5)
                        }.padding(6)
                    }
                    .frame(width: max(54, proxy.size.width * min(0.94, max(0.30, item.frame.width))),
                           height: max(40, proxy.size.height * min(0.90, max(0.36, item.frame.height))))
                    .offset(x: max(2, proxy.size.width * item.frame.minX * 0.12), y: max(18, proxy.size.height * item.frame.minY * 0.12))
                    .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
            }
        }
    }
}

@MainActor
final class CleanSpacePanel {
    private let panels: [NSPanel]
    private let targetFrames: [CGRect]
    init(screen: NSScreen, background: NSColor) {
        let bounds = screen.visibleFrame
        let leftFrame = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width / 2, height: bounds.height)
        let rightFrame = CGRect(x: leftFrame.maxX, y: bounds.minY, width: bounds.width - leftFrame.width, height: bounds.height)
        let frames = [leftFrame, rightFrame]
        targetFrames = frames
        panels = frames.enumerated().map { index, frame in
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.isOpaque = true
            panel.backgroundColor = background
            panel.ignoresMouseEvents = true
            panel.level = .normal
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.hasShadow = false
            panel.alphaValue = 1
            if index == 0 { panel.setFrame(frame.offsetBy(dx: -frame.width, dy: 0), display: false) }
            else { panel.setFrame(frame.offsetBy(dx: frame.width, dy: 0), display: false) }
            return panel
        }
    }
    func setBackground(_ color: NSColor) { panels.forEach { $0.backgroundColor = color } }
    func show() {
        for panel in panels { panel.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            for (index, panel) in panels.enumerated() {
                panel.animator().setFrame(targetFrames[index], display: true)
            }
        }
    }
    func close() { panels.forEach { $0.orderOut(nil) } }
}

@MainActor
final class NoPeekPanel {
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let effectViews = (0..<4).map { _ in NSVisualEffectView() }
    private let dimView = NSView()
    private var lastFrame: CGRect?
    private var lastFocusRect: CGRect?
    private var lastDimAmount: CGFloat?
    private var lastBlur: Bool?

    init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        // Keep status-bar popovers and app menus above the dimming surface.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        for effect in effectViews {
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
        }
        dimView.wantsLayer = true
        let content = NSView(frame: panel.frame)
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        dimView.autoresizingMask = [.width, .height]
        effectViews.forEach { panel.contentView?.addSubview($0) }
        panel.contentView?.addSubview(dimView)
    }

    func show(on screen: NSScreen, focusRect: CGRect?, dimAmount: CGFloat, blur: Bool) {
        let frame = screen.visibleFrame
        let needsUpdate = lastFrame != frame || lastFocusRect != focusRect || lastDimAmount != dimAmount || lastBlur != blur
        if needsUpdate {
            panel.setFrame(frame, display: true)
            panel.contentView?.frame = CGRect(origin: .zero, size: frame.size)
            let bounds = panel.contentView?.bounds ?? CGRect(origin: .zero, size: frame.size)
            dimView.frame = bounds
            dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(dimAmount).cgColor
            let mask = CAShapeLayer()
            mask.frame = bounds
            let path = CGMutablePath()
            path.addRect(bounds)
            var blurRegions: [CGRect] = [bounds]
            if let focusRect {
                let expanded = focusRect.insetBy(dx: -3, dy: -3).intersection(bounds)
                if !expanded.isEmpty {
                    path.addRoundedRect(in: expanded, cornerWidth: 10, cornerHeight: 10)
                    blurRegions = [
                        CGRect(x: bounds.minX, y: expanded.maxY, width: bounds.width, height: bounds.maxY - expanded.maxY),
                        CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: expanded.minY - bounds.minY),
                        CGRect(x: bounds.minX, y: expanded.minY, width: expanded.minX - bounds.minX, height: expanded.height),
                        CGRect(x: expanded.maxX, y: expanded.minY, width: bounds.maxX - expanded.maxX, height: expanded.height)
                    ]
                }
            }
            mask.path = path
            mask.fillRule = .evenOdd
            dimView.layer?.mask = mask
            for (index, effect) in effectViews.enumerated() {
                let region = blurRegions.indices.contains(index) ? blurRegions[index] : .zero
                effect.frame = region
                effect.isHidden = !blur || region.isEmpty
            }
            lastFrame = frame
            lastFocusRect = focusRect
            lastDimAmount = dimAmount
            lastBlur = blur
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func close() { panel.orderOut(nil) }
}
