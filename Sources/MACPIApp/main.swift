import AppKit
import QuartzCore
import Darwin
import Foundation
import IOKit.ps
import MACPIAppSupport

enum AppLayout {
    static let sidebarWidth: CGFloat = 0
    static let sidebarHorizontalInset: CGFloat = 22
    static let sidebarTopInset: CGFloat = 28
    static let sidebarBottomInset: CGFloat = 22
    static let contentHorizontalInset: CGFloat = 44
    static let contentTopInset: CGFloat = 32
    static let contentBottomInset: CGFloat = 156
    static let contentMaxWidth: CGFloat = 980
    static let contentSectionSpacing: CGFloat = 18
    static let statusGridSpacing: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let sectionCardPadding: CGFloat = 18
    static let buttonRowSpacing: CGFloat = 10
    static let buttonGridSpacing: CGFloat = 12
    static let bottomDockHeight: CGFloat = 64
    static let bottomDockOuterHeight: CGFloat = 92
    static let bottomDockBottomInset: CGFloat = 42
    static let bottomDockMaxWidth: CGFloat = 636
    static let windowWidth: CGFloat = 1120
    static let windowHeight: CGFloat = 760
    static let windowMinWidth: CGFloat = 960
    static let windowMinHeight: CGFloat = 680
}

enum AppPowerState: String {
    case ac = "AC Power"
    case battery = "Battery Power"
    case unknown = "Unknown"

    var displayName: String {
        switch self {
        case .ac:
            return L10n.text(zh: "插电", en: "AC Power")
        case .battery:
            return L10n.text(zh: "电池", en: "Battery")
        case .unknown:
            return L10n.text(zh: "未知", en: "Unknown")
        }
    }
}

struct AppPowerSource {
    static func current() -> AppPowerState {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let unmanaged = IOPSGetProvidingPowerSourceType(info) else {
            return .unknown
        }

        let source = unmanaged.takeUnretainedValue() as String
        if source == (kIOPSACPowerValue as String) {
            return .ac
        }
        if source == (kIOPSBatteryPowerValue as String) {
            return .battery
        }
        return .unknown
    }
}

struct AppCPUInfo {
    let performanceCores: Int?
    let efficiencyCores: Int?

    static func current() -> AppCPUInfo {
        AppCPUInfo(
            performanceCores: sysctlInt("hw.perflevel0.physicalcpu"),
            efficiencyCores: sysctlInt("hw.perflevel1.physicalcpu")
        )
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let status = sysctlbyname(name, &value, &size, nil, 0)
        return status == 0 ? Int(value) : nil
    }
}

struct AppStatusSnapshot {
    let power: AppPowerState
    let cpu: AppCPUInfo
    let helperAvailable: Bool
    let daemonRunning: Bool

    static func current() -> AppStatusSnapshot {
        let helper = AppBundlePaths.helperPath()
        let daemon = AppCommandRunner.run("/bin/launchctl", ["print", "system/com.local.macpi"])
        return AppStatusSnapshot(
            power: AppPowerSource.current(),
            cpu: AppCPUInfo.current(),
            helperAvailable: FileManager.default.isExecutableFile(atPath: helper),
            daemonRunning: daemon.exitCode == 0
        )
    }
}

enum AppBundlePaths {
    static func helperPath() -> String {
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("macpi"),
           FileManager.default.isExecutableFile(atPath: resourceURL.path) {
            return resourceURL.path
        }

        let executableDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let sibling = executableDir.appendingPathComponent("macpi").path
        if FileManager.default.isExecutableFile(atPath: sibling) {
            return sibling
        }

        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/release/macpi")
            .path
        return local
    }

    static func appIconPath() -> String? {
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns"),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL.path
        }
        return nil
    }
}

enum SidebarSection {
    case performance
    case processes
    case hardware
    case diagnostics
    case settings

    static let navigationCases: [SidebarSection] = [.performance, .processes, .hardware, .diagnostics]

    var title: String {
        switch self {
        case .performance:
            return "MACPI"
        case .processes:
            return L10n.text(zh: "进程分析", en: "Process Analysis")
        case .hardware:
            return L10n.text(zh: "硬件状态", en: "Hardware Status")
        case .diagnostics:
            return L10n.text(zh: "诊断输出", en: "Diagnostics")
        case .settings:
            return L10n.text(zh: "设置", en: "Settings")
        }
    }

    var subtitle: String {
        switch self {
        case .performance:
            return "powered by zhangdoudou"
        case .processes:
            return L10n.text(zh: "查看哪些进程会被加速、跳过或保护", en: "Inspect which processes are boosted, skipped, or protected")
        case .hardware:
            return L10n.text(zh: "核心拓扑与实时负载", en: "Core topology and live load")
        case .diagnostics:
            return L10n.text(zh: "自测、Dry Run 与运行日志", en: "Self-test, dry run, and logs")
        case .settings:
            return L10n.text(zh: "策略、语言与应用偏好", en: "Policy, language, and app preferences")
        }
    }

    var sidebarTitle: String {
        switch self {
        case .performance:
            return L10n.text(zh: "性能策略", en: "Performance")
        case .processes:
            return L10n.text(zh: "进程分析", en: "Processes")
        case .hardware:
            return L10n.text(zh: "硬件状态", en: "Hardware")
        case .diagnostics:
            return L10n.text(zh: "诊断输出", en: "Diagnostics")
        case .settings:
            return L10n.text(zh: "设置", en: "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .performance:
            return "bolt.fill"
        case .processes:
            return "list.bullet.rectangle"
        case .hardware:
            return "cpu"
        case .diagnostics:
            return "terminal"
        case .settings:
            return "gearshape"
        }
    }
}

enum AppPolicyMode: Int, CaseIterable {
    case balanced = 0
    case performance = 1
    case aggressive = 2

    var argument: String {
        switch self {
        case .balanced:
            return "balanced"
        case .performance:
            return "performance"
        case .aggressive:
            return "aggressive"
        }
    }

    var title: String {
        switch self {
        case .balanced:
            return L10n.text(zh: "平衡", en: "Balanced")
        case .performance:
            return L10n.text(zh: "性能", en: "Performance")
        case .aggressive:
            return L10n.text(zh: "激进", en: "Aggressive")
        }
    }

    var detail: String {
        switch self {
        case .balanced:
            return L10n.text(zh: "只处理已被系统后台化的进程，不触碰高性能电源档。", en: "Only boosts already-backgrounded processes and leaves high-power settings alone.")
        case .performance:
            return L10n.text(zh: "默认推荐：插电时解除后台调度限制，不修改低电量或电源模式。", en: "Recommended: clears background policy on AC without changing Low Power or power mode settings.")
        case .aggressive:
            return L10n.text(zh: "在性能模式基础上追加 renice，适合短时重负载。", en: "Adds renice on top of Performance mode for short heavy workloads.")
        }
    }
}

extension NSBezierPath {
    var macpiCGPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }

        return path
    }
}

final class DashboardBackgroundView: NSView {
    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.082, alpha: 1).setFill()
        bounds.fill()

        NSGradient(colors: [
            NSColor(calibratedRed: 0.105, green: 0.135, blue: 0.175, alpha: 1),
            NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.082, alpha: 1),
            NSColor(calibratedRed: 0.035, green: 0.040, blue: 0.052, alpha: 1)
        ])?.draw(in: bounds, angle: -90)

        NSGradient(colors: [
            NSColor.controlAccentColor.withAlphaComponent(0.13),
            NSColor.systemTeal.withAlphaComponent(0.07),
            NSColor.clear
        ])?.draw(in: bounds, angle: -90)

        let centerWidth = min(AppLayout.contentMaxWidth + 96, bounds.width)
        let centerRect = NSRect(x: (bounds.width - centerWidth) / 2, y: 0, width: centerWidth, height: bounds.height)
        NSGradient(colors: [
            NSColor.clear,
            NSColor.white.withAlphaComponent(0.055),
            NSColor.clear
        ])?.draw(in: centerRect, angle: 0)

    }
}

final class CardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.64).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.40).cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 18
        layer?.shadowOffset = NSSize(width: 0, height: -6)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.075),
            NSColor.white.withAlphaComponent(0.025),
            NSColor.black.withAlphaComponent(0.08)
        ])?.draw(in: path, angle: -90)

        NSColor.white.withAlphaComponent(0.10).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class TileView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.055).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.055),
            NSColor.white.withAlphaComponent(0.018)
        ])?.draw(in: path, angle: -90)

        NSColor.white.withAlphaComponent(0.09).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class QuickEnableHeroView: NSView {
    var isPolicyEnabled = true {
        didSet {
            needsDisplay = true
        }
    }

    init(isPolicyEnabled: Bool) {
        self.isPolicyEnabled = isPolicyEnabled
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.42).cgColor
        layer?.shadowOpacity = 0.20
        layer?.shadowRadius = 22
        layer?.shadowOffset = NSSize(width: 0, height: -7)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        let accent = NSColor.controlAccentColor
        let secondary = isPolicyEnabled ? NSColor.systemTeal : NSColor.secondaryLabelColor

        NSGradient(colors: [
            accent.withAlphaComponent(isPolicyEnabled ? 0.32 : 0.12),
            secondary.withAlphaComponent(isPolicyEnabled ? 0.18 : 0.08),
            NSColor.black.withAlphaComponent(0.10)
        ])?.draw(in: path, angle: 0)

        NSColor.white.withAlphaComponent(isPolicyEnabled ? 0.11 : 0.06).setFill()
        path.fill()

        NSColor.white.withAlphaComponent(isPolicyEnabled ? 0.22 : 0.12).setStroke()
        path.lineWidth = 1
        path.stroke()

        let glowRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width * 0.42, height: rect.height)
        NSGradient(colors: [
            accent.withAlphaComponent(isPolicyEnabled ? 0.26 : 0.08),
            NSColor.clear
        ])?.draw(in: glowRect, angle: 0)
    }
}

final class SetupGuideOverlayView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        isHidden = true
        alphaValue = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        let focusRect = NSRect(
            x: bounds.midX - min(bounds.width * 0.42, 420),
            y: bounds.midY - 220,
            width: min(bounds.width * 0.84, 840),
            height: 440
        )
        NSGradient(colors: [
            NSColor.controlAccentColor.withAlphaComponent(0.11),
            NSColor.systemTeal.withAlphaComponent(0.07),
            NSColor.clear
        ])?.draw(in: focusRect, angle: -90)
    }
}

final class LiquidGlassDockView: NSView {
    private var capsuleRect: NSRect {
        let verticalInset = max(0, (bounds.height - AppLayout.bottomDockHeight) / 2)
        return NSRect(
            x: 0.5,
            y: verticalInset,
            width: max(1, bounds.width - 1),
            height: AppLayout.bottomDockHeight
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = AppLayout.bottomDockOuterHeight / 2
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.shadowOpacity = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = capsuleRect
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: AppLayout.bottomDockHeight / 2,
            yRadius: AppLayout.bottomDockHeight / 2
        )
        layer?.shadowPath = path.macpiCGPath

        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.30),
            NSColor.white.withAlphaComponent(0.10),
            NSColor.black.withAlphaComponent(0.16)
        ])?.draw(in: path, angle: -90)

        NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.15, alpha: 0.66).setFill()
        path.fill()

        let colorWash = NSBezierPath(
            roundedRect: rect.insetBy(dx: 7, dy: 8),
            xRadius: AppLayout.bottomDockHeight / 2 - 8,
            yRadius: AppLayout.bottomDockHeight / 2 - 8
        )
        NSGradient(colors: [
            NSColor.controlAccentColor.withAlphaComponent(0.18),
            NSColor.systemTeal.withAlphaComponent(0.08),
            NSColor.clear
        ])?.draw(in: colorWash, angle: 0)

        NSColor.white.withAlphaComponent(0.46).setStroke()
        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: rect.minX + 28, y: rect.minY + 10))
        highlight.curve(
            to: NSPoint(x: rect.maxX - 28, y: rect.minY + 11),
            controlPoint1: NSPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + 2),
            controlPoint2: NSPoint(x: rect.minX + rect.width * 0.68, y: rect.minY + 2)
        )
        highlight.lineWidth = 1
        highlight.stroke()

        NSColor.white.withAlphaComponent(0.18).setStroke()
        let inner = NSBezierPath(
            roundedRect: rect.insetBy(dx: 7, dy: 7),
            xRadius: AppLayout.bottomDockHeight / 2 - 7,
            yRadius: AppLayout.bottomDockHeight / 2 - 7
        )
        inner.lineWidth = 1
        inner.stroke()

        NSColor.white.withAlphaComponent(0.30).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class LiquidSelectionPillView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 19
        layer?.shadowColor = NSColor.controlAccentColor.withAlphaComponent(0.38).cgColor
        layer?.shadowOpacity = 0.24
        layer?.shadowRadius = 14
        layer?.shadowOffset = NSSize(width: 0, height: -2)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 19, yRadius: 19)
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.50),
            NSColor.controlAccentColor.withAlphaComponent(0.22),
            NSColor.systemTeal.withAlphaComponent(0.13)
        ])?.draw(in: path, angle: -90)

        NSColor.white.withAlphaComponent(0.68).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class SidebarItemControl: NSControl {
    let section: SidebarSection
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var isPressed = false

    var isSelectedItem = false {
        didSet {
            updateAppearance()
        }
    }

    init(section: SidebarSection, target: AnyObject?, action: Selector) {
        self.section = section
        super.init(frame: .zero)
        self.target = target
        self.action = action
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        isPressed = false
        updateAppearance()
        if bounds.contains(location), let action {
            sendAction(action, to: target)
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        iconView.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.sidebarTitle)
        iconView.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = section.sidebarTitle
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    func refreshLanguage() {
        iconView.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.sidebarTitle)
        titleLabel.stringValue = section.sidebarTitle
    }

    private func updateAppearance() {
        let accent = NSColor.controlAccentColor
        let selectedAlpha: CGFloat = isPressed ? 0.20 : 0.14
        let normalAlpha: CGFloat = isPressed ? 0.08 : 0
        layer?.backgroundColor = isSelectedItem
            ? accent.withAlphaComponent(selectedAlpha).cgColor
            : NSColor.labelColor.withAlphaComponent(normalAlpha).cgColor
        iconView.contentTintColor = isSelectedItem ? accent : .secondaryLabelColor
        titleLabel.font = .systemFont(ofSize: 14, weight: isSelectedItem ? .semibold : .medium)
        titleLabel.textColor = isSelectedItem ? .labelColor : .secondaryLabelColor
    }
}

final class BottomNavItemControl: NSControl {
    let section: SidebarSection
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var isPressed = false

    var isSelectedItem = false {
        didSet {
            updateAppearance()
        }
    }

    init(section: SidebarSection, target: AnyObject?, action: Selector) {
        self.section = section
        super.init(frame: .zero)
        self.target = target
        self.action = action
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        isPressed = false
        updateAppearance()
        if bounds.contains(location), let action {
            sendAction(action, to: target)
        }
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 18

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        iconView.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.sidebarTitle)
        iconView.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = section.sidebarTitle
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 38),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 104),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    func refreshLanguage() {
        iconView.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.sidebarTitle)
        titleLabel.stringValue = section.sidebarTitle
    }

    private func updateAppearance() {
        let accent = NSColor.controlAccentColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(isPressed ? 0.10 : 0).cgColor
        iconView.contentTintColor = isSelectedItem ? accent : .secondaryLabelColor
        titleLabel.textColor = isSelectedItem ? .labelColor : .secondaryLabelColor
    }
}

final class CPUCoreChartView: NSView {
    private var usages: [Double] = []
    private var efficiencyCoreCount = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.42).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(usages: [Double], efficiencyCoreCount: Int) {
        self.usages = usages
        self.efficiencyCoreCount = max(0, min(efficiencyCoreCount, usages.count))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !usages.isEmpty else {
            drawEmptyState()
            return
        }

        let inset = NSEdgeInsets(top: 34, left: 22, bottom: 34, right: 22)
        let chartRect = NSRect(
            x: bounds.minX + inset.left,
            y: bounds.minY + inset.bottom,
            width: bounds.width - inset.left - inset.right,
            height: bounds.height - inset.top - inset.bottom
        )

        drawGrid(in: chartRect)
        drawClusterLabels(in: chartRect)

        let gap: CGFloat = 8
        let barWidth = max(6, (chartRect.width - gap * CGFloat(max(0, usages.count - 1))) / CGFloat(usages.count))

        for (index, usage) in usages.enumerated() {
            let heightRatio = CGFloat(min(100, max(0, usage)) / 100)
            let barHeight = max(3, chartRect.height * heightRatio)
            let x = chartRect.minX + CGFloat(index) * (barWidth + gap)
            let y = chartRect.minY
            let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let isEfficiencyCore = index < efficiencyCoreCount
            let color = isEfficiencyCore ? NSColor.systemGreen : NSColor.controlAccentColor

            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            NSGradient(colors: [
                color.withAlphaComponent(0.98),
                color.withAlphaComponent(0.62)
            ])?.draw(in: path, angle: 90)

            if index == 0 || index == efficiencyCoreCount || usages.count <= 12 {
                drawLabel(
                    isEfficiencyCore ? "E\(index + 1)" : "P\(max(1, index - efficiencyCoreCount + 1))",
                    in: NSRect(x: x - 6, y: chartRect.minY - 25, width: barWidth + 12, height: 16)
                )
            }
        }
    }

    private func drawGrid(in rect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.24).setStroke()
        for ratio in [0.25, 0.5, 0.75, 1.0] {
            let y = rect.minY + rect.height * CGFloat(ratio)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rect.maxX, y: y))
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawClusterLabels(in rect: NSRect) {
        guard !usages.isEmpty else {
            return
        }

        let gap: CGFloat = 8
        let barWidth = max(6, (rect.width - gap * CGFloat(max(0, usages.count - 1))) / CGFloat(usages.count))

        if efficiencyCoreCount > 0 {
            let width = CGFloat(efficiencyCoreCount) * barWidth + CGFloat(max(0, efficiencyCoreCount - 1)) * gap
            drawClusterLabel(
                L10n.text(zh: "E 核", en: "E Cores"),
                color: .systemGreen,
                in: NSRect(x: rect.minX, y: rect.maxY + 8, width: width, height: 16)
            )
        }

        let performanceCount = max(0, usages.count - efficiencyCoreCount)
        if performanceCount > 0 {
            let startX = rect.minX + CGFloat(efficiencyCoreCount) * (barWidth + gap)
            let width = CGFloat(performanceCount) * barWidth + CGFloat(max(0, performanceCount - 1)) * gap
            drawClusterLabel(
                L10n.text(zh: "P 核", en: "P Cores"),
                color: .controlAccentColor,
                in: NSRect(x: startX, y: rect.maxY + 8, width: width, height: 16)
            )
        }
    }

    private func drawClusterLabel(_ text: String, color: NSColor, in rect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (text as NSString).draw(in: rect, withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: color.withAlphaComponent(0.92),
            .paragraphStyle: style
        ])
    }

    private func drawLabel(_ text: String, in rect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (text as NSString).draw(in: rect, withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style
        ])
    }

    private func drawEmptyState() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (L10n.text(zh: "读取中", en: "Loading") as NSString).draw(in: bounds.insetBy(dx: 20, dy: bounds.height / 2 - 10), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style
        ])
    }
}

final class StatusBadge: NSView {
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")

    init(text: String, color: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = color.withAlphaComponent(0.10).cgColor

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dot)
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        set(text: text, color: color)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(text: String, color: NSColor) {
        label.stringValue = text
        label.textColor = color
        dot.layer?.backgroundColor = color.cgColor
        layer?.backgroundColor = color.withAlphaComponent(0.10).cgColor
    }
}

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool {
        true
    }
}

final class FullWidthStackView: NSStackView {
    override func addArrangedSubview(_ view: NSView) {
        super.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        let width = view.widthAnchor.constraint(equalTo: widthAnchor)
        width.priority = .defaultHigh
        width.isActive = true
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool {
        true
    }
}

final class DashboardViewController: NSViewController, @unchecked Sendable {
    private static let defaultProtectedWhitelist = [
        "backupd",
        "bird",
        "cloudphotod",
        "cloudd",
        "mds",
        "mdworker",
        "mdworker_shared",
        "photoanalysisd",
        "photolibraryd"
    ]

    private let contentScrollView = NSScrollView()
    private let contentDocument = FlippedView()
    private let contentStack = FlippedStackView()
    private let powerValue = NSTextField(labelWithString: L10n.text(zh: "读取中", en: "Loading"))
    private let coreValue = NSTextField(labelWithString: L10n.text(zh: "读取中", en: "Loading"))
    private let helperValue = NSTextField(labelWithString: L10n.text(zh: "读取中", en: "Loading"))
    private let daemonValue = NSTextField(labelWithString: L10n.text(zh: "读取中", en: "Loading"))
    private let efficiencyAverageValue = NSTextField(labelWithString: L10n.text(zh: "E 平均 --%", en: "E Avg --%"))
    private let performanceAverageValue = NSTextField(labelWithString: L10n.text(zh: "P 平均 --%", en: "P Avg --%"))
    private let cpuPeakValue = NSTextField(labelWithString: L10n.text(zh: "峰值 --%", en: "Peak --%"))
    private let cpuActiveCoreValue = NSTextField(labelWithString: L10n.text(zh: "活跃 --", en: "Active --"))
    private let powerBadge = StatusBadge(text: L10n.text(zh: "读取中", en: "Loading"), color: .secondaryLabelColor)
    private let daemonBadge = StatusBadge(text: L10n.text(zh: "服务状态", en: "Service"), color: .secondaryLabelColor)
    private let cpuChartView = CPUCoreChartView()
    private let cpuMonitor = AppCPUCoreMonitor()
    private let outputView = NSTextView()
    private let installCommand = NSTextField(labelWithString: L10n.text(zh: "内置 helper -> /usr/local/sbin/macpi", en: "Bundled helper -> /usr/local/sbin/macpi"))
    private let intervalField = NSTextField(string: "15")
    private let reapplyField = NSTextField(string: "60")
    private let policyEnabledToggle = NSButton(checkboxWithTitle: L10n.text(zh: "启用 MACPI 策略", en: "Enable MACPI policy"), target: nil, action: nil)
    private let quickEnableSwitch = NSSwitch()
    private let policyModeSlider = NSSlider(value: 0, minValue: 0, maxValue: 2, target: nil, action: nil)
    private let policyModeValue = NSTextField(labelWithString: AppPolicyMode.balanced.title)
    private let policyModeDetail = NSTextField(labelWithString: AppPolicyMode.balanced.detail)
    private let restoreToggle = NSButton(checkboxWithTitle: L10n.text(zh: "电池时恢复原本后台状态", en: "Restore original background state on battery"), target: nil, action: nil)
    private let protectSystemToggle = NSButton(checkboxWithTitle: L10n.text(zh: "保护系统关键进程", en: "Protect system-critical processes"), target: nil, action: nil)
    private let whitelistField = NSTextField(string: DashboardViewController.defaultProtectedWhitelist.joined(separator: ", "))
    private let processAnalysisView = NSTextView()
    private let setupGuideOverlay = SetupGuideOverlayView()
    private var sidebarItems: [SidebarSection: SidebarItemControl] = [:]
    private var bottomNavItems: [SidebarSection: BottomNavItemControl] = [:]
    private let bottomSelectionIndicator = LiquidSelectionPillView()
    private var bottomSelectionLeadingConstraint: NSLayoutConstraint?
    private var bottomSelectionWidthConstraint: NSLayoutConstraint?
    private var settingsButton: NSButton?
    private var selectedSection: SidebarSection = .performance
    private var contentTransitionDirection: CGFloat = 1
    private var contentReloadTask: Task<Void, Never>?
    private let cpuTimer = AppTimerBox()
    private var lastCPUUsages: [Double] = []
    private var lastSnapshot: AppStatusSnapshot?
    private var setupGuideDismissedForSession = false
    private var didConfigurePolicyFields = false
    private var didConfigureCPUChart = false

    override func loadView() {
        view = DashboardBackgroundView()
        view.wantsLayer = true
        buildLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .appLanguageDidChange,
            object: nil
        )
        policyEnabledToggle.state = .on
        quickEnableSwitch.state = .on
        protectSystemToggle.state = .on
        restoreToggle.state = .on
        configureQuickEnableSwitch()
        configurePolicyModeSlider()
        outputView.string = L10n.text(
            zh: "MACPI GUI 已就绪。\n建议先运行自测，再安装 LaunchDaemon。",
            en: "MACPI GUI is ready.\nRun self-test before installing the LaunchDaemon."
        )
        processAnalysisView.string = L10n.text(
            zh: "点击“刷新分析”查看当前进程会被加速、跳过或保护的原因。",
            en: "Click Refresh Analysis to inspect why processes will be boosted, skipped, or protected."
        )
        reloadContent()
        refreshStatus()
        startCPUUpdates()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        cpuTimer.invalidate()
    }

    @objc private func languageDidChange() {
        policyEnabledToggle.title = L10n.text(zh: "启用 MACPI 策略", en: "Enable MACPI policy")
        restoreToggle.title = L10n.text(zh: "电池时恢复原本后台状态", en: "Restore original background state on battery")
        protectSystemToggle.title = L10n.text(zh: "保护系统关键进程", en: "Protect system-critical processes")
        whitelistField.placeholderString = L10n.text(zh: "例如：backupd, mds, photoanalysisd", en: "Example: backupd, mds, photoanalysisd")
        updatePolicyModeLabels()
        installCommand.stringValue = L10n.text(zh: "内置 helper -> /usr/local/sbin/macpi", en: "Bundled helper -> /usr/local/sbin/macpi")
        sidebarItems.values.forEach { $0.refreshLanguage() }
        bottomNavItems.values.forEach { $0.refreshLanguage() }
        settingsButton?.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: SidebarSection.settings.sidebarTitle)
        settingsButton?.toolTip = SidebarSection.settings.sidebarTitle
        reloadContent()
        refreshStatus()
        refreshCPUChart()
    }

    private func configureQuickEnableSwitch() {
        quickEnableSwitch.controlSize = .large
        quickEnableSwitch.target = self
        quickEnableSwitch.action = #selector(quickEnableChanged)
    }

    private func configurePolicyModeSlider() {
        policyModeSlider.minValue = 0
        policyModeSlider.maxValue = 2
        policyModeSlider.numberOfTickMarks = 3
        policyModeSlider.allowsTickMarkValuesOnly = true
        policyModeSlider.isContinuous = false
        policyModeSlider.target = self
        policyModeSlider.action = #selector(policyModeChanged)
        policyModeSlider.controlSize = .large
        policyModeSlider.doubleValue = Double(AppPolicyMode.balanced.rawValue)
        updatePolicyModeLabels()
    }

    private var selectedPolicyMode: AppPolicyMode {
        AppPolicyMode(rawValue: Int(policyModeSlider.integerValue)) ?? .balanced
    }

    @objc private func policyModeChanged() {
        updatePolicyModeLabels()
    }

    @objc private func policyControlChanged() {
        quickEnableSwitch.state = policyEnabledToggle.state
        if selectedSection == .performance || selectedSection == .settings || selectedSection == .processes {
            reloadContent()
        }
    }

    @objc private func quickEnableChanged() {
        policyEnabledToggle.state = quickEnableSwitch.state
        policyControlChanged()
    }

    private func updatePolicyModeLabels() {
        let mode = selectedPolicyMode
        policyModeValue.stringValue = mode.title
        policyModeDetail.stringValue = mode.detail
    }

    private func buildLayout() {
        let content = makeContent()
        let bottomDock = makeBottomDock()
        content.translatesAutoresizingMaskIntoConstraints = false
        bottomDock.translatesAutoresizingMaskIntoConstraints = false
        setupGuideOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        view.addSubview(bottomDock)
        view.addSubview(setupGuideOverlay)

        let preferredDockWidth = bottomDock.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -96)
        preferredDockWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bottomDock.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bottomDock.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -AppLayout.bottomDockBottomInset),
            bottomDock.heightAnchor.constraint(equalToConstant: AppLayout.bottomDockOuterHeight),
            preferredDockWidth,
            bottomDock.widthAnchor.constraint(lessThanOrEqualToConstant: AppLayout.bottomDockMaxWidth),
            bottomDock.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),

            setupGuideOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            setupGuideOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            setupGuideOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            setupGuideOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func makeBottomDock() -> NSView {
        let dock = LiquidGlassDockView()

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        dock.addSubview(stack)

        bottomSelectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        dock.addSubview(bottomSelectionIndicator, positioned: .below, relativeTo: stack)

        let sections: [SidebarSection] = SidebarSection.navigationCases + [.settings]
        sections.forEach { section in
            let item = BottomNavItemControl(section: section, target: self, action: #selector(selectBottomSection))
            item.isSelectedItem = section == selectedSection
            bottomNavItems[section] = item
            stack.addArrangedSubview(item)
        }

        let indicatorLeading = bottomSelectionIndicator.leadingAnchor.constraint(equalTo: stack.leadingAnchor)
        let indicatorWidth = bottomSelectionIndicator.widthAnchor.constraint(equalToConstant: 104)
        bottomSelectionLeadingConstraint = indicatorLeading
        bottomSelectionWidthConstraint = indicatorWidth

        NSLayoutConstraint.activate([
            bottomSelectionIndicator.centerYAnchor.constraint(equalTo: stack.centerYAnchor),
            bottomSelectionIndicator.heightAnchor.constraint(equalToConstant: 38),
            indicatorLeading,
            indicatorWidth,
            stack.leadingAnchor.constraint(equalTo: dock.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: dock.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: dock.centerYAnchor)
        ])

        DispatchQueue.main.async { [weak self] in
            self?.updateBottomSelectionIndicator(animated: false)
        }
        return dock
    }

    private func makeSidebar() -> NSView {
        let container = NSVisualEffectView()
        container.material = .sidebar
        container.blendingMode = .behindWindow
        container.state = .active

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let brand = NSStackView()
        brand.orientation = .horizontal
        brand.alignment = .centerY
        brand.spacing = 10

        let mark = NSView()
        mark.wantsLayer = true
        mark.layer?.cornerRadius = 10
        mark.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.82).cgColor
        mark.layer?.borderWidth = 1
        mark.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.30).cgColor
        mark.layer?.shadowColor = NSColor.black.withAlphaComponent(0.14).cgColor
        mark.layer?.shadowOpacity = 0.16
        mark.layer?.shadowRadius = 8
        mark.layer?.shadowOffset = NSSize(width: 0, height: -1)
        mark.translatesAutoresizingMaskIntoConstraints = false
        let markIcon = NSImageView()
        if let iconPath = AppBundlePaths.appIconPath() {
            markIcon.image = NSImage(contentsOfFile: iconPath)
            markIcon.imageScaling = .scaleProportionallyUpOrDown
        } else {
            markIcon.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "MACPI")
            markIcon.symbolConfiguration = .init(pointSize: 17, weight: .bold)
            markIcon.contentTintColor = .controlAccentColor
        }
        markIcon.translatesAutoresizingMaskIntoConstraints = false
        mark.addSubview(markIcon)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 36),
            mark.heightAnchor.constraint(equalToConstant: 36),
            markIcon.widthAnchor.constraint(equalToConstant: 31),
            markIcon.heightAnchor.constraint(equalToConstant: 31),
            markIcon.centerXAnchor.constraint(equalTo: mark.centerXAnchor),
            markIcon.centerYAnchor.constraint(equalTo: mark.centerYAnchor)
        ])

        let brandText = NSStackView()
        brandText.orientation = .vertical
        brandText.spacing = 2
        let title = NSTextField(labelWithString: "MACPI")
        title.font = .systemFont(ofSize: 21, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Performance Control")
        subtitle.font = .systemFont(ofSize: 11, weight: .medium)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        subtitle.lineBreakMode = .byWordWrapping
        brandText.addArrangedSubview(title)
        brandText.addArrangedSubview(subtitle)

        let settings = NSButton(title: "", target: self, action: #selector(selectSettings))
        settings.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: SidebarSection.settings.sidebarTitle)
        settings.toolTip = SidebarSection.settings.sidebarTitle
        settings.bezelStyle = .rounded
        settings.controlSize = .small
        settings.translatesAutoresizingMaskIntoConstraints = false
        settingsButton = settings

        brand.addArrangedSubview(mark)
        brand.addArrangedSubview(brandText)
        brand.addArrangedSubview(NSView())
        brand.addArrangedSubview(settings)

        stack.addArrangedSubview(brand)
        stack.setCustomSpacing(24, after: brand)
        SidebarSection.navigationCases.forEach { section in
            let item = SidebarItemControl(section: section, target: self, action: #selector(selectSection))
            item.isSelectedItem = section == selectedSection
            sidebarItems[section] = item
            stack.addArrangedSubview(item)
        }
        stack.addArrangedSubview(NSView())

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: AppLayout.sidebarHorizontalInset),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -AppLayout.sidebarHorizontalInset),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: AppLayout.sidebarTopInset),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -AppLayout.sidebarBottomInset),
            settings.widthAnchor.constraint(equalToConstant: 30),
            settings.heightAnchor.constraint(equalToConstant: 28)
        ])

        return container
    }

    private func makeContent() -> NSView {
        contentScrollView.drawsBackground = false
        contentScrollView.hasVerticalScroller = true
        contentScrollView.autohidesScrollers = true
        contentScrollView.scrollerStyle = .overlay
        contentScrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: AppLayout.bottomDockOuterHeight + AppLayout.bottomDockBottomInset + 56,
            right: 0
        )

        contentDocument.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.documentView = contentDocument

        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.distribution = .fill
        contentStack.spacing = AppLayout.contentSectionSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.wantsLayer = true
        contentDocument.addSubview(contentStack)

        let preferredContentWidth = contentStack.widthAnchor.constraint(
            equalTo: contentDocument.widthAnchor,
            constant: -AppLayout.contentHorizontalInset * 2
        )
        preferredContentWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            contentDocument.widthAnchor.constraint(equalTo: contentScrollView.contentView.widthAnchor),
            contentDocument.heightAnchor.constraint(greaterThanOrEqualTo: contentScrollView.contentView.heightAnchor),
            contentStack.centerXAnchor.constraint(equalTo: contentDocument.centerXAnchor),
            preferredContentWidth,
            contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: AppLayout.contentMaxWidth),
            contentStack.widthAnchor.constraint(lessThanOrEqualTo: contentDocument.widthAnchor, constant: -AppLayout.contentHorizontalInset * 2),
            contentStack.topAnchor.constraint(equalTo: contentDocument.topAnchor, constant: AppLayout.contentTopInset),
            contentStack.bottomAnchor.constraint(equalTo: contentDocument.bottomAnchor, constant: -AppLayout.contentBottomInset)
        ])

        return contentScrollView
    }

    @objc private func selectSection(_ sender: SidebarItemControl) {
        guard selectedSection != sender.section else {
            return
        }
        contentTransitionDirection = transitionDirection(from: selectedSection, to: sender.section)
        selectedSection = sender.section
        updateSidebarSelection()
        reloadContent(animated: true)
        refreshStatus()
        refreshCPUChart()
    }

    @objc private func selectBottomSection(_ sender: BottomNavItemControl) {
        guard selectedSection != sender.section else {
            return
        }
        contentTransitionDirection = transitionDirection(from: selectedSection, to: sender.section)
        selectedSection = sender.section
        updateSidebarSelection()
        reloadContent(animated: true)
        refreshStatus()
        refreshCPUChart()
    }

    @objc private func selectSettings() {
        guard selectedSection != .settings else {
            return
        }
        contentTransitionDirection = transitionDirection(from: selectedSection, to: .settings)
        selectedSection = .settings
        updateSidebarSelection()
        reloadContent(animated: true)
        refreshStatus()
        refreshCPUChart()
    }

    private func updateSidebarSelection() {
        sidebarItems.forEach { section, item in
            item.isSelectedItem = section == selectedSection
        }
        bottomNavItems.forEach { section, item in
            item.isSelectedItem = section == selectedSection
        }
        updateBottomSelectionIndicator(animated: true)
        settingsButton?.contentTintColor = selectedSection == .settings ? .controlAccentColor : .secondaryLabelColor
        settingsButton?.toolTip = SidebarSection.settings.sidebarTitle
    }

    private func transitionDirection(from oldSection: SidebarSection, to newSection: SidebarSection) -> CGFloat {
        let order = SidebarSection.navigationCases + [.settings]
        guard let oldIndex = order.firstIndex(of: oldSection),
              let newIndex = order.firstIndex(of: newSection),
              oldIndex != newIndex else {
            return 1
        }
        return newIndex > oldIndex ? 1 : -1
    }

    private func updateBottomSelectionIndicator(animated: Bool) {
        guard let item = bottomNavItems[selectedSection],
              let dock = bottomSelectionIndicator.superview,
              let leadingConstraint = bottomSelectionLeadingConstraint,
              let widthConstraint = bottomSelectionWidthConstraint else {
            return
        }

        let frameInDock = item.convert(item.bounds, to: dock)
        dock.layoutSubtreeIfNeeded()
        bottomSelectionIndicator.layer?.removeAllAnimations()
        leadingConstraint.constant = frameInDock.minX - 10
        widthConstraint.constant = frameInDock.width

        guard animated else {
            dock.layoutSubtreeIfNeeded()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.90, 0.24, 1.0)
            dock.animator().layoutSubtreeIfNeeded()
        }
    }

    private func reloadContent(animated: Bool = false) {
        contentReloadTask?.cancel()
        contentStack.layer?.removeAnimation(forKey: "MACPIContentSlideIn")

        guard animated else {
            contentStack.alphaValue = 1
            rebuildContent()
            updateSetupGuideOverlay(animated: false)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            contentStack.animator().alphaValue = 0
        }

        contentReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else {
                self?.contentStack.alphaValue = 1
                return
            }
            guard let self else {
                return
            }
            self.rebuildContent()
            self.contentStack.alphaValue = 0
            self.animateContentSlideIn(direction: self.contentTransitionDirection)
            NSAnimationContext.beginGrouping()
            let context = NSAnimationContext.current
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.contentStack.animator().alphaValue = 1
            NSAnimationContext.endGrouping()
            self.updateSetupGuideOverlay(animated: true)
            self.contentReloadTask = nil
        }
    }

    private func animateContentSlideIn(direction: CGFloat) {
        guard let layer = contentStack.layer else {
            return
        }
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = 18 * direction
        slide.toValue = 0
        slide.duration = 0.22
        slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(slide, forKey: "MACPIContentSlideIn")
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { subview in
            contentStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        var sections: [NSView]
        switch selectedSection {
        case .performance:
            sections = [
                makeHeader(),
                makeStatusGrid(),
                makeQuickEnablePanel(),
                makePerformanceOverviewPanel()
            ]
        case .processes:
            sections = [
                makeHeader(),
                makeStatusGrid(),
                makeProcessAnalysisPanel()
            ]
        case .hardware:
            sections = [
                makeHeader(),
                makeStatusGrid(),
                makeCPUChartPanel(),
                makeHardwareSummaryPanel(),
                makeHardwareToolsPanel()
            ]
        case .diagnostics:
            sections = [
                makeHeader(),
                makeDiagnosticActionsPanel(),
                makeOutputPanel()
            ]
        case .settings:
            sections = [
                makeHeader(),
                makePolicyPanel(),
                makeAppSettingsPanel(),
                makeOperationsPanel()
            ]
        }

        sections.forEach { section in
            section.translatesAutoresizingMaskIntoConstraints = false
            contentStack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        let dockSpacer = NSView()
        dockSpacer.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(dockSpacer)
        dockSpacer.heightAnchor.constraint(equalToConstant: AppLayout.bottomDockOuterHeight + AppLayout.bottomDockBottomInset + 68).isActive = true
        dockSpacer.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        contentScrollView.contentView.scroll(to: .zero)
    }

    private func homeSetupGuideNeeded(for snapshot: AppStatusSnapshot) -> Bool {
        !snapshot.helperAvailable || !snapshot.daemonRunning
    }

    private func shouldShowHomeSetupGuide() -> Bool {
        guard selectedSection == .performance, !setupGuideDismissedForSession else {
            return false
        }
        if let lastSnapshot {
            return homeSetupGuideNeeded(for: lastSnapshot)
        }
        return homeSetupGuideNeeded(for: AppStatusSnapshot.current())
    }

    private func rebuildSetupGuideOverlayContent() {
        setupGuideOverlay.subviews.forEach { $0.removeFromSuperview() }
        let card = makeHomeSetupGuidePopup()
        card.translatesAutoresizingMaskIntoConstraints = false
        setupGuideOverlay.addSubview(card)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: setupGuideOverlay.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: setupGuideOverlay.centerYAnchor, constant: -18),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            card.widthAnchor.constraint(lessThanOrEqualTo: setupGuideOverlay.widthAnchor, constant: -72),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 420)
        ])
    }

    private func updateSetupGuideOverlay(animated: Bool) {
        let shouldShow = shouldShowHomeSetupGuide()
        if shouldShow {
            rebuildSetupGuideOverlayContent()
            setupGuideOverlay.isHidden = false
            setupGuideOverlay.needsDisplay = true
            guard animated else {
                setupGuideOverlay.alphaValue = 1
                return
            }
            setupGuideOverlay.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                setupGuideOverlay.animator().alphaValue = 1
            }
            return
        }

        guard !setupGuideOverlay.isHidden else {
            return
        }
        guard animated else {
            setupGuideOverlay.alphaValue = 0
            setupGuideOverlay.isHidden = true
            setupGuideOverlay.subviews.forEach { $0.removeFromSuperview() }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            setupGuideOverlay.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.setupGuideOverlay.isHidden = true
                self?.setupGuideOverlay.subviews.forEach { $0.removeFromSuperview() }
            }
        }
    }

    private func makeHomeSetupGuidePopup() -> NSView {
        let card = makeSectionCard(
            title: L10n.text(zh: "完成首次设置", zhHant: "完成首次設定", yue: "完成首次設定", en: "Finish Setup"),
            subtitle: L10n.text(
                zh: "检测到 helper 或 LaunchDaemon 尚未就绪，安装后首页会自动恢复为日常仪表盘。",
                zhHant: "偵測到 helper 或 LaunchDaemon 尚未就緒，安裝後首頁會自動恢復成日常儀表板。",
                yue: "偵測到 helper 或 LaunchDaemon 未準備好，安裝後首頁會自動回復做日常儀表板。",
                en: "Helper or LaunchDaemon is not ready. After installation, this page returns to the daily dashboard."
            )
        )
        let body = card.subviews.compactMap { $0 as? NSStackView }.first!
        let snapshot = lastSnapshot ?? AppStatusSnapshot.current()

        body.addArrangedSubview(makeGrid(
            rows: [[
                makeInfoPill(
                    title: "Helper",
                    value: snapshot.helperAvailable
                        ? L10n.text(zh: "可用", en: "Ready")
                        : L10n.text(zh: "未找到", en: "Missing")
                ),
                makeInfoPill(
                    title: "LaunchDaemon",
                    value: snapshot.daemonRunning
                        ? L10n.text(zh: "运行中", en: "Running")
                        : L10n.text(zh: "未安装", en: "Not Installed")
                ),
                makeInfoPill(
                    title: L10n.text(zh: "默认白名单", zhHant: "預設白名單", yue: "預設白名單", en: "Default Whitelist"),
                    value: "\(whitelistedProcessNames().count)"
                )
            ]],
            spacing: AppLayout.buttonGridSpacing
        ))

        let buttons = makeGrid(
            rows: [[
                makeButton(title: L10n.text(zh: "安装/更新服务", en: "Install / Update"), symbol: "arrow.down.circle", action: #selector(installService), role: .primary),
                makeButton(title: L10n.text(zh: "运行自测", en: "Self-Test"), symbol: "checkmark.seal", action: #selector(runSelfTest)),
                makeButton(title: L10n.text(zh: "打开设置", zhHant: "打開設定", yue: "打開設定", en: "Open Settings"), symbol: "gearshape", action: #selector(selectSettings))
            ], [
                makeButton(title: L10n.text(zh: "稍后", zhHant: "稍後", yue: "遲啲先", en: "Later"), symbol: "xmark", action: #selector(dismissSetupGuide))
            ]],
            spacing: AppLayout.buttonGridSpacing
        )
        body.addArrangedSubview(buttons)
        return card
    }

    private func makeHeader() -> NSView {
        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .centerX
        header.spacing = 12

        let texts = NSStackView()
        texts.orientation = .vertical
        texts.alignment = .centerX
        texts.spacing = 4
        let title = NSTextField(labelWithString: selectedSection.title)
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.alignment = .center
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byWordWrapping
        let subtitle = NSTextField(labelWithString: selectedSection.subtitle)
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2
        subtitle.lineBreakMode = .byWordWrapping
        texts.addArrangedSubview(title)
        texts.addArrangedSubview(subtitle)

        let badgeStack = NSStackView()
        badgeStack.orientation = .horizontal
        badgeStack.spacing = 8
        badgeStack.addArrangedSubview(powerBadge)
        badgeStack.addArrangedSubview(daemonBadge)

        let refresh = NSButton(title: "", target: self, action: #selector(refreshStatus))
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: L10n.text(zh: "刷新", en: "Refresh"))
        refresh.toolTip = L10n.text(zh: "刷新状态", en: "Refresh status")
        refresh.bezelStyle = .rounded

        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 10
        statusRow.addArrangedSubview(badgeStack)
        statusRow.addArrangedSubview(refresh)

        header.addArrangedSubview(texts)
        header.addArrangedSubview(statusRow)
        return header
    }

    private func makeStatusGrid() -> NSView {
        return makeGrid(
            rows: [
                [
                    makeMetricCard(title: L10n.text(zh: "供电状态", en: "Power"), value: powerValue, symbol: "powerplug.fill"),
                    makeMetricCard(title: L10n.text(zh: "核心拓扑", en: "Core Topology"), value: coreValue, symbol: "cpu.fill"),
                    makeMetricCard(title: "Helper", value: helperValue, symbol: "wrench.and.screwdriver.fill"),
                    makeMetricCard(title: "LaunchDaemon", value: daemonValue, symbol: "gearshape.2.fill")
                ]
            ],
            spacing: AppLayout.statusGridSpacing
        )
    }

    private func makeQuickEnablePanel() -> NSView {
        let card = QuickEnableHeroView(isPolicyEnabled: policyEnabledToggle.state == .on)
        card.translatesAutoresizingMaskIntoConstraints = false
        configureQuickEnableSwitch()
        quickEnableSwitch.state = policyEnabledToggle.state

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        let iconWrap = NSView()
        iconWrap.wantsLayer = true
        iconWrap.layer?.cornerRadius = 17
        iconWrap.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(policyEnabledToggle.state == .on ? 0.24 : 0.10).cgColor
        iconWrap.layer?.borderWidth = 1
        iconWrap.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        iconWrap.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: policyEnabledToggle.state == .on ? "bolt.fill" : "power", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 28, weight: .bold)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.addSubview(icon)

        let texts = NSStackView()
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 5

        let title = NSTextField(labelWithString: policyEnabledToggle.state == .on
            ? L10n.text(zh: "一键性能已开启", zhHant: "一鍵性能已開啟", yue: "一鍵性能已開啟", en: "One-Click Performance On")
            : L10n.text(zh: "一键开启性能策略", zhHant: "一鍵開啟性能策略", yue: "一鍵開啟性能策略", en: "Enable Performance in One Click"))
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.maximumNumberOfLines = 1

        let subtitle = NSTextField(labelWithString: policyEnabledToggle.state == .on
            ? L10n.text(zh: "当前模式：\(selectedPolicyMode.title)，点击右侧可立即暂停策略", zhHant: "目前模式：\(selectedPolicyMode.title)，點擊右側可即時暫停策略", yue: "目前模式：\(selectedPolicyMode.title)，撳右邊可以即刻暫停策略", en: "Current mode: \(selectedPolicyMode.title). Toggle on the right to pause instantly.")
            : L10n.text(zh: "开启后按当前模式自动应用调度策略", zhHant: "開啟後按目前模式自動套用調度策略", yue: "開啟後會按目前模式自動套用調度策略", en: "Uses the current mode to apply scheduling policy automatically."))
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2
        subtitle.lineBreakMode = .byWordWrapping

        texts.addArrangedSubview(title)
        texts.addArrangedSubview(subtitle)

        row.addArrangedSubview(iconWrap)
        row.addArrangedSubview(texts)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(quickEnableSwitch)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 136),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28),
            row.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconWrap.widthAnchor.constraint(equalToConstant: 68),
            iconWrap.heightAnchor.constraint(equalToConstant: 68),
            icon.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor)
        ])

        return card
    }

    private func makePerformanceOverviewPanel() -> NSView {
        let card = makeSectionCard(
            title: L10n.text(zh: "当前策略", en: "Current Policy"),
            subtitle: L10n.text(zh: "插电时优先性能，电池时恢复保守策略", en: "Performance-first on AC, conservative behavior on battery")
        )
        let body = card.subviews.compactMap { $0 as? NSStackView }.first!

        body.addArrangedSubview(makePolicyOverviewDashboard())
        return card
    }

    private func makePolicyOverviewDashboard() -> NSView {
        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .height
        row.spacing = AppLayout.buttonGridSpacing
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        let summary = makePolicySummaryTile()
        let details = makeGrid(
            rows: [
                [
                    makePolicyDetailTile(
                        title: L10n.text(zh: "插电策略", en: "AC Policy"),
                        value: selectedPolicyMode == .balanced
                            ? L10n.text(zh: "只处理后台", en: "Background Only")
                            : L10n.text(zh: "清除限制", en: "Boost")
                    ),
                    makePolicyDetailTile(
                        title: L10n.text(zh: "电池策略", en: "Battery Policy"),
                        value: restoreToggle.state == .on
                            ? L10n.text(zh: "恢复原状", en: "Restore")
                            : L10n.text(zh: "保持现状", en: "Leave As-Is")
                    )
                ],
                [
                    makePolicyDetailTile(
                        title: L10n.text(zh: "扫描间隔", en: "Scan Interval"),
                        value: "\(intervalField.stringValue)s"
                    ),
                    makePolicyDetailTile(
                        title: L10n.text(zh: "系统保护", en: "System Guard"),
                        value: protectSystemToggle.state == .on
                            ? L10n.text(zh: "开启", en: "On")
                            : L10n.text(zh: "关闭", en: "Off")
                    )
                ]
            ],
            spacing: AppLayout.buttonGridSpacing
        )

        row.addArrangedSubview(summary)
        row.addArrangedSubview(details)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            summary.widthAnchor.constraint(equalToConstant: 280),
            details.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -292)
        ])

        return container
    }

    private func makePolicySummaryTile() -> NSView {
        let box = TileView()
        box.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)

        let eyebrow = NSTextField(labelWithString: L10n.text(zh: "策略模式", en: "Policy Mode"))
        eyebrow.font = .systemFont(ofSize: 12, weight: .semibold)
        eyebrow.textColor = .secondaryLabelColor

        let mode = NSTextField(labelWithString: selectedPolicyMode.title)
        mode.font = .systemFont(ofSize: 28, weight: .bold)
        mode.maximumNumberOfLines = 1

        let state = NSTextField(labelWithString: policyEnabledToggle.state == .on
            ? L10n.text(zh: "策略已启用，白名单 \(whitelistedProcessNames().count)", zhHant: "策略已啟用，白名單 \(whitelistedProcessNames().count)", yue: "策略已啟用，白名單 \(whitelistedProcessNames().count)", en: "Enabled, whitelist \(whitelistedProcessNames().count)")
            : L10n.text(zh: "策略已暂停", zhHant: "策略已暫停", yue: "策略已暫停", en: "Policy paused"))
        state.font = .systemFont(ofSize: 12, weight: .medium)
        state.textColor = .secondaryLabelColor
        state.maximumNumberOfLines = 2

        stack.addArrangedSubview(eyebrow)
        stack.addArrangedSubview(mode)
        stack.addArrangedSubview(state)

        NSLayoutConstraint.activate([
            box.heightAnchor.constraint(equalToConstant: 164),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -18),
            stack.centerYAnchor.constraint(equalTo: box.centerYAnchor)
        ])

        return box
    }

    private func makePolicyDetailTile(title: String, value: String) -> NSView {
        let box = TileView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.maximumNumberOfLines = 1

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .systemFont(ofSize: 20, weight: .bold)
        valueLabel.maximumNumberOfLines = 1
        valueLabel.lineBreakMode = .byTruncatingTail

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(valueLabel)

        NSLayoutConstraint.activate([
            box.heightAnchor.constraint(equalToConstant: 76),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: box.centerYAnchor)
        ])

        return box
    }

    private func makeCPUChartPanel() -> NSView {
        let card = makeSectionCard(
            title: L10n.text(zh: "每核心 CPU 占用率", en: "Per-Core CPU Usage"),
            subtitle: L10n.text(zh: "按 Apple Silicon 常见逻辑顺序显示：E 核在前，P 核在后", en: "Uses the common Apple Silicon logical order: E cores first, P cores after")
        )
        let body = card.subviews.compactMap { $0 as? NSStackView }.first!

        if !didConfigureCPUChart {
            cpuChartView.heightAnchor.constraint(equalToConstant: 240).isActive = true
            didConfigureCPUChart = true
        }

        body.addArrangedSubview(makeGrid(
            rows: [[
                makeCompactStat(title: L10n.text(zh: "E 核平均", en: "E-Core Avg"), value: efficiencyAverageValue, symbol: "leaf.fill"),
                makeCompactStat(title: L10n.text(zh: "P 核平均", en: "P-Core Avg"), value: performanceAverageValue, symbol: "bolt.fill"),
                makeCompactStat(title: L10n.text(zh: "峰值核心", en: "Peak Core"), value: cpuPeakValue, symbol: "chart.bar.fill"),
                makeCompactStat(title: L10n.text(zh: "活跃核心", en: "Active Cores"), value: cpuActiveCoreValue, symbol: "cpu")
            ]],
            spacing: AppLayout.buttonGridSpacing
        ))
        body.addArrangedSubview(cpuChartView)
        return card
    }

    private func makeHardwareSummaryPanel() -> NSView {
        let card = makeSectionCard(
            title: L10n.text(zh: "硬件概览", en: "Hardware Overview"),
            subtitle: L10n.text(zh: "当前机器的核心布局", en: "Core layout on this Mac")
        )
        let body = card.subviews.compactMap { $0 as? NSStackView }.first!

        let cpu = AppCPUInfo.current()
        body.addArrangedSubview(makeGrid(
            rows: [[
                makeInfoPill(title: L10n.text(zh: "性能核心", en: "Performance Cores"), value: cpu.performanceCores.map { "\($0)" } ?? "?"),
                makeInfoPill(title: L10n.text(zh: "能效核心", en: "Efficiency Cores"), value: cpu.efficiencyCores.map { "\($0)" } ?? "?"),
                makeInfoPill(title: L10n.text(zh: "采样核心", en: "Sampled Cores"), value: "\(cpuChartViewCoreCount())")
            ]],
            spacing: AppLayout.buttonGridSpacing
        ))
        return card
    }

    private func makeHardwareToolsPanel() -> NSView {
        let card = makeSectionCard(
            title: L10n.text(zh: "硬件工具", en: "Hardware Tools"),
            subtitle: L10n.text(zh: "快速打开系统工具或复制当前硬件摘要", en: "Open system tools or copy the current hardware summary")
        )
        let body = card.subviews.compactMap { $0 as? NSStackView }.first!

        let buttons = NSStackView()
        buttons.orientation = .vertical
        buttons.spacing = AppLayout.buttonRowSpacing
        buttons.addArrangedSubview(makeGrid(
            rows: [[
                makeButton(title: L10n.text(zh: "打开活动监视器", en: "Open Activity Monitor"), symbol: "waveform.path.ecg", action: #selector(openActivityMonitor), role: .primary),
                makeButton(title: L10n.text(zh: "复制硬件摘要", en: "Copy Hardware Summary"), symbol: "doc.on.doc", action: #selector(copyHardwareSummary))
            ]],
            spacing: AppLayout.buttonGridSpacing
        ))
        buttons.addArrangedSubview(makeGrid(
            rows: [[
                makeButton(title: L10n.text(zh: "刷新图表", en: "Refresh Chart"), symbol: "arrow.clockwise", action: #selector(refreshCPUChart))
            ]],
            spacing: AppLayout.buttonGridSpacing
        ))
        body.addArrangedSubview(buttons)
        return card
    }

    private func makeAppSettingsPanel() -> NSView {
        let card = makeSectionCard(
            title: L10n.text(zh: "应用设置", en: "App Settings"),
            subtitle: L10n.text(zh: "语言、菜单栏和核心图表显示", en: "Language, menu bar, and CPU chart display")
        )
        let body = card.subviews.compactMap { $0 as? NSStackView }.first!

        let languageRow = NSStackView()
        languageRow.orientation = .horizontal
        languageRow.alignment = .centerY
        languageRow.spacing = 12
        let languageLabel = NSTextField(labelWithString: L10n.text(zh: "语言", en: "Language"))
        languageLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        languageLabel.widthAnchor.constraint(equalToConstant: AppLanguage.effective == .english ? 142 : 96).isActive = true
        let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        AppLanguage.allCases.forEach { language in
            languagePopup.addItem(withTitle: language.menuTitle)
            languagePopup.lastItem?.representedObject = language.rawValue
        }
        if let index = AppLanguage.allCases.firstIndex(of: AppLanguage.selected) {
            languagePopup.selectItem(at: index)
        }
        languagePopup.target = self
        languagePopup.action = #selector(changeLanguageFromPopup)
        languageRow.addArrangedSubview(languageLabel)
        languageRow.addArrangedSubview(languagePopup)

        body.addArrangedSubview(languageRow)
        body.addArrangedSubview(makeGrid(
            rows: [[
                makeInfoPill(title: L10n.text(zh: "菜单栏图标", en: "Menu Bar"), value: L10n.text(zh: "已启用", en: "Enabled")),
                makeInfoPill(title: L10n.text(zh: "核心映射", en: "Core Mapping"), value: L10n.text(zh: "E → P", en: "E -> P")),
                makeInfoPill(title: L10n.text(zh: "图表刷新", en: "Chart Refresh"), value: "1s")
            ]],
            spacing: AppLayout.buttonGridSpacing
        ))
        return card
    }

    private func makeDiagnosticActionsPanel() -> NSView {
        let card = makeSectionCard(
            title: L10n.text(zh: "诊断操作", en: "Diagnostic Actions"),
            subtitle: L10n.text(zh: "运行检查并收集输出", en: "Run checks and collect output")
        )
        let body = card.subviews.compactMap { $0 as? NSStackView }.first!

        let buttons = NSStackView()
        buttons.orientation = .vertical
        buttons.spacing = AppLayout.buttonRowSpacing
        buttons.addArrangedSubview(makeGrid(
            rows: [[
                makeButton(title: L10n.text(zh: "运行自测", en: "Self-Test"), symbol: "checkmark.seal", action: #selector(runSelfTest), role: .primary),
                makeButton(title: "Dry Run", symbol: "play.circle", action: #selector(runDryRun))
            ]],
            spacing: AppLayout.buttonGridSpacing
        ))
        buttons.addArrangedSubview(makeGrid(
            rows: [[
                makeButton(title: L10n.text(zh: "复制日志命令", en: "Copy Log Command"), symbol: "text.alignleft", action: #selector(copyLogCommand)),
                makeButton(title: L10n.text(zh: "刷新状态", en: "Refresh Status"), symbol: "arrow.clockwise", action: #selector(refreshStatus))
            ]],
            spacing: AppLayout.buttonGridSpacing
        ))
        body.addArrangedSubview(buttons)
        return card
    }

    private func makeProcessAnalysisPanel() -> NSView {
        let card = makeSectionCard(
            title: L10n.text(zh: "进程分析", en: "Process Analysis"),
            subtitle: L10n.text(zh: "按当前 GUI 策略预估哪些进程会被加速、跳过或保护。", en: "Uses the current GUI policy to show which processes will be boosted, skipped, or protected.")
        )
        let body = card.subviews.compactMap { $0 as? NSStackView }.first!

        let buttons = NSStackView()
        buttons.orientation = .vertical
        buttons.spacing = AppLayout.buttonRowSpacing
        buttons.addArrangedSubview(makeGrid(
            rows: [[
                makeButton(title: L10n.text(zh: "刷新分析", en: "Refresh Analysis"), symbol: "arrow.clockwise", action: #selector(refreshProcessAnalysis), role: .primary),
                makeButton(title: L10n.text(zh: "复制分析", en: "Copy Analysis"), symbol: "doc.on.doc", action: #selector(copyProcessAnalysis))
            ]],
            spacing: AppLayout.buttonGridSpacing
        ))
        buttons.addArrangedSubview(makeGrid(
            rows: [[
                makeButton(title: L10n.text(zh: "打开活动监视器", en: "Open Activity Monitor"), symbol: "waveform.path.ecg", action: #selector(openActivityMonitor))
            ]],
            spacing: AppLayout.buttonGridSpacing
        ))

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        processAnalysisView.isEditable = false
        processAnalysisView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        processAnalysisView.textColor = .labelColor
        processAnalysisView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.78)
        processAnalysisView.textContainerInset = NSSize(width: 12, height: 12)
        scroll.documentView = processAnalysisView
        scroll.heightAnchor.constraint(equalToConstant: 360).isActive = true

        body.addArrangedSubview(makeGrid(
            rows: [[
                makeInfoPill(title: L10n.text(zh: "总开关", en: "Master Switch"), value: policyEnabledToggle.state == .on ? L10n.text(zh: "开启", en: "On") : L10n.text(zh: "关闭", en: "Off")),
                makeInfoPill(title: L10n.text(zh: "模式", en: "Mode"), value: selectedPolicyMode.title),
                makeInfoPill(title: L10n.text(zh: "白名单", en: "Whitelist"), value: "\(whitelistedProcessNames().count)"),
                makeInfoPill(title: L10n.text(zh: "系统关键", en: "System Critical"), value: protectSystemToggle.state == .on ? L10n.text(zh: "保护", en: "Protected") : L10n.text(zh: "允许", en: "Allowed"))
            ]],
            spacing: AppLayout.buttonGridSpacing
        ))
        body.addArrangedSubview(buttons)
        body.addArrangedSubview(scroll)
        return card
    }

    private func makeCompactStat(title: String, value: NSTextField, symbol: String) -> NSView {
        let card = TileView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        icon.contentTintColor = .controlAccentColor

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping

        value.font = .monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        value.alignment = .center
        value.maximumNumberOfLines = 2
        value.lineBreakMode = .byWordWrapping

        row.addArrangedSubview(icon)
        row.addArrangedSubview(label)
        stack.addArrangedSubview(row)
        stack.addArrangedSubview(value)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 78),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        return card
    }

    private func makeInfoPill(title: String, value: String) -> NSView {
        let box = TileView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        valueLabel.alignment = .center
        valueLabel.maximumNumberOfLines = 2
        valueLabel.lineBreakMode = .byWordWrapping

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(valueLabel)

        NSLayoutConstraint.activate([
            box.heightAnchor.constraint(equalToConstant: 82),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: box.centerYAnchor)
        ])
        return box
    }

    private func cpuChartViewCoreCount() -> Int {
        let cpu = AppCPUInfo.current()
        return (cpu.performanceCores ?? 0) + (cpu.efficiencyCores ?? 0)
    }

    private func makeMetricCard(title: String, value: NSTextField, symbol: String) -> NSView {
        let card = CardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let iconWrap = NSView()
        iconWrap.wantsLayer = true
        iconWrap.layer?.cornerRadius = 7
        iconWrap.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        iconWrap.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.addSubview(icon)

        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 12, weight: .semibold)
        name.textColor = .secondaryLabelColor
        name.alignment = .center
        name.maximumNumberOfLines = 2
        name.lineBreakMode = .byWordWrapping
        value.font = .monospacedDigitSystemFont(ofSize: 23, weight: .bold)
        value.alignment = .center
        value.maximumNumberOfLines = 2
        value.lineBreakMode = .byWordWrapping

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.addArrangedSubview(iconWrap)
        row.addArrangedSubview(name)
        stack.addArrangedSubview(row)
        stack.addArrangedSubview(value)

        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 104),
            iconWrap.widthAnchor.constraint(equalToConstant: 30),
            iconWrap.heightAnchor.constraint(equalToConstant: 30),
            icon.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func makePolicyPanel() -> NSView {
        let card = makeSectionCard(
            title: L10n.text(zh: "策略配置", en: "Policy Configuration"),
            subtitle: L10n.text(zh: "这些参数对应 LaunchDaemon 的运行参数。", en: "These values map to LaunchDaemon runtime arguments.")
        )
        let body = card.subviews.compactMap { $0 as? NSStackView }.first!

        let form = NSStackView()
        form.orientation = .vertical
        form.spacing = 12
        form.alignment = .width
        form.translatesAutoresizingMaskIntoConstraints = false
        intervalField.maximumNumberOfLines = 1
        reapplyField.maximumNumberOfLines = 1
        intervalField.alignment = .right
        reapplyField.alignment = .right
        intervalField.controlSize = .large
        reapplyField.controlSize = .large
        intervalField.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        reapplyField.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        if !didConfigurePolicyFields {
            intervalField.widthAnchor.constraint(equalToConstant: 72).isActive = true
            reapplyField.widthAnchor.constraint(equalToConstant: 72).isActive = true
            whitelistField.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
            didConfigurePolicyFields = true
        }
        policyEnabledToggle.controlSize = .large
        restoreToggle.controlSize = .large
        protectSystemToggle.controlSize = .large
        [policyEnabledToggle, restoreToggle, protectSystemToggle].forEach { toggle in
            toggle.target = self
            toggle.action = #selector(policyControlChanged)
        }
        whitelistField.controlSize = .large
        whitelistField.placeholderString = L10n.text(zh: "例如：backupd, mds, photoanalysisd", en: "Example: backupd, mds, photoanalysisd")
        whitelistField.target = self
        whitelistField.action = #selector(policyControlChanged)

        body.addArrangedSubview(makePolicyModePanel())
        form.addArrangedSubview(makeFormRow(title: L10n.text(zh: "扫描间隔", en: "Scan Interval"), field: intervalField, unit: L10n.text(zh: "秒", en: "sec")))
        form.addArrangedSubview(makeFormRow(title: L10n.text(zh: "同 PID 刷新", en: "Same PID Refresh"), field: reapplyField, unit: L10n.text(zh: "秒", en: "sec")))
        form.addArrangedSubview(makeFormRow(title: L10n.text(zh: "保护白名单", en: "Whitelist"), field: whitelistField, unit: L10n.text(zh: "不干预", en: "protected")))
        body.addArrangedSubview(makeCenteredContainer(form, maxWidth: 820))

        let toggleStack = NSStackView()
        toggleStack.orientation = .vertical
        toggleStack.alignment = .leading
        toggleStack.spacing = 8
        toggleStack.addArrangedSubview(policyEnabledToggle)
        toggleStack.addArrangedSubview(restoreToggle)
        toggleStack.addArrangedSubview(protectSystemToggle)
        body.addArrangedSubview(makeCenteredContainer(toggleStack, maxWidth: 820))
        return card
    }

    private func makePolicyModePanel() -> NSView {
        let box = TileView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)

        let labelStack = NSStackView()
        labelStack.orientation = .vertical
        labelStack.alignment = .centerX
        labelStack.spacing = 3
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: L10n.text(zh: "模式滑杆", en: "Mode Slider"))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.alignment = .center
        policyModeValue.font = .systemFont(ofSize: 20, weight: .bold)
        policyModeValue.alignment = .center
        policyModeValue.maximumNumberOfLines = 1
        policyModeValue.lineBreakMode = .byTruncatingTail
        policyModeDetail.font = .systemFont(ofSize: 12, weight: .regular)
        policyModeDetail.textColor = .secondaryLabelColor
        policyModeDetail.alignment = .center
        policyModeDetail.maximumNumberOfLines = 2
        policyModeDetail.lineBreakMode = .byWordWrapping
        labelStack.addArrangedSubview(title)
        labelStack.addArrangedSubview(policyModeValue)
        labelStack.addArrangedSubview(policyModeDetail)

        let sliderStack = NSStackView()
        sliderStack.orientation = .vertical
        sliderStack.alignment = .width
        sliderStack.spacing = 6
        sliderStack.translatesAutoresizingMaskIntoConstraints = false
        policyModeSlider.translatesAutoresizingMaskIntoConstraints = false
        let ticks = NSStackView()
        ticks.orientation = .horizontal
        ticks.distribution = .fillEqually
        ticks.alignment = .centerY
        ticks.addArrangedSubview(makeTinyLabel(AppPolicyMode.balanced.title, alignment: .center))
        ticks.addArrangedSubview(makeTinyLabel(AppPolicyMode.performance.title, alignment: .center))
        ticks.addArrangedSubview(makeTinyLabel(AppPolicyMode.aggressive.title, alignment: .center))
        sliderStack.addArrangedSubview(policyModeSlider)
        sliderStack.addArrangedSubview(ticks)

        stack.addArrangedSubview(labelStack)
        stack.addArrangedSubview(sliderStack)

        let preferredSliderWidth = sliderStack.widthAnchor.constraint(equalToConstant: 380)
        preferredSliderWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            box.heightAnchor.constraint(greaterThanOrEqualToConstant: 124),
            labelStack.widthAnchor.constraint(lessThanOrEqualTo: box.widthAnchor, constant: -56),
            policyModeDetail.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
            preferredSliderWidth,
            sliderStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            sliderStack.widthAnchor.constraint(lessThanOrEqualTo: box.widthAnchor, constant: -96),
            ticks.widthAnchor.constraint(equalTo: sliderStack.widthAnchor),
            policyModeSlider.widthAnchor.constraint(equalTo: sliderStack.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -16)
        ])

        updatePolicyModeLabels()
        return box
    }

    private func makeTinyLabel(_ text: String, alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = alignment
        return label
    }

    private func makeFormRow(title: String, field: NSTextField, unit: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.widthAnchor.constraint(equalToConstant: AppLanguage.effective == .english ? 142 : 96).isActive = true

        let unitLabel = NSTextField(labelWithString: unit)
        unitLabel.font = .systemFont(ofSize: 13, weight: .medium)
        unitLabel.textColor = .secondaryLabelColor

        row.addArrangedSubview(label)
        row.addArrangedSubview(field)
        row.addArrangedSubview(unitLabel)
        row.addArrangedSubview(NSView())
        return row
    }

    private func makeOperationsPanel() -> NSView {
        let card = makeSectionCard(
            title: L10n.text(zh: "操作", en: "Actions"),
            subtitle: L10n.text(zh: "安装需要管理员权限；GUI 会生成命令，核心服务仍以 root LaunchDaemon 运行。", en: "Installation requires administrator privileges; the service runs as a root LaunchDaemon.")
        )
        let body = card.subviews.compactMap { $0 as? NSStackView }.first!

        installCommand.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        installCommand.textColor = .secondaryLabelColor

        let buttons = NSStackView()
        buttons.orientation = .vertical
        buttons.spacing = AppLayout.buttonRowSpacing
        buttons.addArrangedSubview(makeGrid(
            rows: [[
                makeButton(title: L10n.text(zh: "安装/更新服务", en: "Install / Update"), symbol: "arrow.down.circle", action: #selector(installService), role: .primary),
                makeButton(title: L10n.text(zh: "卸载服务", en: "Uninstall"), symbol: "trash", action: #selector(uninstallService), role: .destructive)
            ]],
            spacing: AppLayout.buttonGridSpacing
        ))
        buttons.addArrangedSubview(makeGrid(
            rows: [[
                makeButton(title: L10n.text(zh: "运行自测", en: "Self-Test"), symbol: "checkmark.seal", action: #selector(runSelfTest)),
                makeButton(title: "Dry Run", symbol: "play.circle", action: #selector(runDryRun)),
                makeButton(title: L10n.text(zh: "复制日志命令", en: "Copy Log Command"), symbol: "text.alignleft", action: #selector(copyLogCommand))
            ]],
            spacing: AppLayout.buttonGridSpacing
        ))

        body.addArrangedSubview(makeAuthorizationStatusGrid())
        body.addArrangedSubview(installCommand)
        body.addArrangedSubview(buttons)
        return card
    }

    private func makeAuthorizationStatusGrid() -> NSView {
        makeGrid(
            rows: [[
                makeInfoPill(
                    title: L10n.text(zh: "授权方式", zhHant: "授權方式", yue: "授權方式", en: "Authorization"),
                    value: L10n.text(zh: "系统弹窗", zhHant: "系統彈窗", yue: "系統彈窗", en: "System Prompt")
                ),
                makeInfoPill(
                    title: L10n.text(zh: "密码保存", zhHant: "密碼保存", yue: "密碼保存", en: "Password Storage"),
                    value: L10n.text(zh: "不保存", zhHant: "不保存", yue: "唔保存", en: "Not Stored")
                ),
                makeInfoPill(
                    title: L10n.text(zh: "日常操作", zhHant: "日常操作", yue: "日常操作", en: "Routine Actions"),
                    value: L10n.text(zh: "免密码", zhHant: "免密碼", yue: "免密碼", en: "No Password")
                )
            ]],
            spacing: AppLayout.buttonGridSpacing
        )
    }

    private func makeOutputPanel() -> NSView {
        let card = makeSectionCard(
            title: L10n.text(zh: "诊断输出", en: "Diagnostic Output"),
            subtitle: L10n.text(zh: "自测和 dry-run 的输出会显示在这里。", en: "Self-test and dry-run output appears here.")
        )
        let body = card.subviews.compactMap { $0 as? NSStackView }.first!

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        outputView.isEditable = false
        outputView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        outputView.textColor = .labelColor
        outputView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.78)
        outputView.textContainerInset = NSSize(width: 12, height: 12)
        scroll.documentView = outputView
        scroll.heightAnchor.constraint(equalToConstant: 190).isActive = true
        body.addArrangedSubview(scroll)
        return card
    }

    private func makeSectionCard(title: String, subtitle: String) -> CardView {
        let card = CardView()
        let stack = FullWidthStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let header = FullWidthStackView()
        header.orientation = .vertical
        header.alignment = .centerX
        header.spacing = 3
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byWordWrapping
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 3
        subtitleLabel.lineBreakMode = .byWordWrapping
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(subtitleLabel)
        stack.addArrangedSubview(header)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: AppLayout.sectionCardPadding),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -AppLayout.sectionCardPadding),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: AppLayout.cardPadding),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -AppLayout.cardPadding)
        ])
        return card
    }

    private enum ButtonRole {
        case normal
        case primary
        case destructive
    }

    private func makeButton(title: String, symbol: String, action: Selector, role: ButtonRole = .normal) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: role == .primary ? .semibold : .medium)
        button.cell?.lineBreakMode = .byTruncatingTail
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        switch role {
        case .primary:
            button.bezelColor = .controlAccentColor
            button.contentTintColor = .white
        case .destructive:
            button.contentTintColor = .systemRed
        case .normal:
            break
        }
        return button
    }

    private func makeCenteredContainer(_ view: NSView, maxWidth: CGFloat) -> NSView {
        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)

        let fillWidth = view.widthAnchor.constraint(equalTo: container.widthAnchor)
        fillWidth.priority = .defaultLow

        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            fillWidth
        ])

        return container
    }

    private func makeGrid(rows: [[NSView]], spacing: CGFloat) -> NSView {
        let container = FlippedView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .width
        grid.spacing = spacing
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)

        rows.forEach { rowViews in
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .height
            row.spacing = spacing
            row.distribution = .fillEqually
            row.translatesAutoresizingMaskIntoConstraints = false
            rowViews.forEach { row.addArrangedSubview($0) }
            grid.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            grid.topAnchor.constraint(equalTo: container.topAnchor),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func startCPUUpdates() {
        refreshCPUChart()
        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(refreshCPUChart),
            userInfo: nil,
            repeats: true
        )
        cpuTimer.replace(with: timer)
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func refreshCPUChart() {
        let usages = cpuMonitor.sample()
        let cpu = AppCPUInfo.current()
        let efficiencyCount = max(0, min(cpu.efficiencyCores ?? 0, usages.count))
        let efficiencyUsages = Array(usages.prefix(efficiencyCount))
        let performanceUsages = Array(usages.dropFirst(efficiencyCount))
        lastCPUUsages = usages
        cpuChartView.update(usages: usages, efficiencyCoreCount: efficiencyCount)

        guard !usages.isEmpty else {
            efficiencyAverageValue.stringValue = L10n.text(zh: "E 平均 --%", en: "E Avg --%")
            performanceAverageValue.stringValue = L10n.text(zh: "P 平均 --%", en: "P Avg --%")
            cpuPeakValue.stringValue = L10n.text(zh: "峰值 --%", en: "Peak --%")
            cpuActiveCoreValue.stringValue = L10n.text(zh: "活跃 --", en: "Active --")
            return
        }

        let efficiencyAverage = average(efficiencyUsages)
        let performanceAverage = average(performanceUsages)
        let peak = usages.max() ?? 0
        let activeCount = usages.filter { $0 >= 10 }.count
        efficiencyAverageValue.stringValue = String(format: "%.0f%%", efficiencyAverage)
        performanceAverageValue.stringValue = String(format: "%.0f%%", performanceAverage)
        cpuPeakValue.stringValue = String(format: "%.0f%%", peak)
        cpuActiveCoreValue.stringValue = "\(activeCount) / \(usages.count)"
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0
        }
        return values.reduce(0, +) / Double(values.count)
    }

    @objc private func refreshStatus() {
        let snapshot = AppStatusSnapshot.current()
        applyStatusSnapshot(snapshot)
    }

    private func applyStatusSnapshot(_ snapshot: AppStatusSnapshot) {
        lastSnapshot = snapshot
        let power = snapshot.power
        powerValue.stringValue = power.displayName
        switch power {
        case .ac:
            powerBadge.set(text: L10n.text(zh: "AC 性能模式", en: "AC Performance"), color: .systemGreen)
        case .battery:
            powerBadge.set(text: L10n.text(zh: "电池保护", en: "Battery Guard"), color: .systemOrange)
        case .unknown:
            powerBadge.set(text: L10n.text(zh: "供电未知", en: "Power Unknown"), color: .secondaryLabelColor)
        }

        let cpu = snapshot.cpu
        coreValue.stringValue = "\(cpu.performanceCores.map(String.init) ?? "?")P / \(cpu.efficiencyCores.map(String.init) ?? "?")E"

        helperValue.stringValue = snapshot.helperAvailable
            ? L10n.text(zh: "可用", en: "Ready")
            : L10n.text(zh: "未找到", en: "Missing")

        daemonValue.stringValue = snapshot.daemonRunning
            ? L10n.text(zh: "运行中", en: "Running")
            : L10n.text(zh: "未安装", en: "Not Installed")
        daemonBadge.set(
            text: snapshot.daemonRunning
                ? L10n.text(zh: "服务运行中", en: "Service Running")
                : L10n.text(zh: "服务未安装", en: "Service Missing"),
            color: snapshot.daemonRunning ? .systemGreen : .secondaryLabelColor
        )

        let currentSetupGuideNeeded = homeSetupGuideNeeded(for: snapshot)
        if !currentSetupGuideNeeded {
            setupGuideDismissedForSession = false
        }
        updateSetupGuideOverlay(animated: true)
    }

    @objc private func dismissSetupGuide() {
        setupGuideDismissedForSession = true
        updateSetupGuideOverlay(animated: true)
    }

    @objc private func runSelfTest() {
        runHelper(arguments: ["self-test"])
    }

    @objc private func runDryRun() {
        runHelper(arguments: ["once", "--dry-run", "--no-power-settings"] + currentPolicyArguments(includeTiming: false))
    }

    @objc private func refreshProcessAnalysis() {
        let arguments = ["analyze", "--limit", "60"] + currentPolicyArguments(includeTiming: false)
        processAnalysisView.string = L10n.text(zh: "正在分析进程...", en: "Analyzing processes...")
        runHelperForProcessAnalysis(arguments: arguments)
    }

    @objc private func copyProcessAnalysis() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(processAnalysisView.string, forType: .string)
        appendOutput(L10n.text(zh: "已复制进程分析结果。", en: "Copied process analysis."))
    }

    @objc private func installService() {
        guard let interval = validatedInteger(from: intervalField.stringValue, minimum: 3),
              let reapply = validatedInteger(from: reapplyField.stringValue, minimum: 3) else {
            appendOutput(L10n.text(
                zh: "安装取消：扫描间隔和同 PID 刷新间隔都必须是 >= 3 的整数。",
                en: "Install canceled: scan interval and same-PID refresh interval must be integers >= 3."
            ))
            return
        }

        let helper = helperPath()
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            appendOutput(L10n.text(
                zh: "安装取消：未找到可执行 helper：\(helper)",
                en: "Install canceled: executable helper was not found: \(helper)"
            ))
            return
        }

        do {
            let arguments = launchDaemonArguments(interval: interval, reapply: reapply)
            if launchDaemonInstallationIsCurrent(arguments: arguments, helperSourcePath: helper) {
                appendOutput(L10n.text(
                    zh: "服务、helper 和当前配置已是最新；无需再次输入管理员密码。",
                    zhHant: "服務、helper 同目前配置已是最新；毋須再次輸入管理員密碼。",
                    yue: "服務、helper 同而家配置已經係最新；唔使再輸入管理員密碼。",
                    en: "The service, helper, and current configuration are already up to date; no administrator password is needed."
                ))
                refreshStatus()
                return
            }
            let plistData = try LaunchDaemonPlistFactory.makePlistData(arguments: arguments)
            let stagedPlist = try writeStagedLaunchDaemonPlist(data: plistData)
            let plan = LaunchDaemonInstallPlan(helperSourcePath: helper, stagedPlistPath: stagedPlist)
            runAdminCommand(plan.shellCommand, label: L10n.text(zh: "安装/更新 LaunchDaemon", en: "Install / Update LaunchDaemon"))
        } catch {
            appendOutput(L10n.text(
                zh: "安装取消：生成 LaunchDaemon plist 失败：\(error)",
                en: "Install canceled: failed to create LaunchDaemon plist: \(error)"
            ))
        }
    }

    @objc private func uninstallService() {
        runAdminCommand(uninstallShellCommand(), label: L10n.text(zh: "卸载 LaunchDaemon", en: "Uninstall LaunchDaemon"))
    }

    @objc private func copyLogCommand() {
        let command = "tail -f /var/log/macpi.log /var/log/macpi.err"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        appendOutput(L10n.text(
            zh: "已复制日志命令：\(command)",
            en: "Copied log command: \(command)"
        ))
    }

    @objc private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
    }

    @objc private func copyHardwareSummary() {
        let snapshot = lastSnapshot ?? AppStatusSnapshot.current()
        let cpu = snapshot.cpu
        let efficiencyCount = cpu.efficiencyCores ?? 0
        let efficiencyAverage = average(Array(lastCPUUsages.prefix(efficiencyCount)))
        let performanceAverage = average(Array(lastCPUUsages.dropFirst(efficiencyCount)))
        let summary = """
        MACPI \(L10n.text(zh: "硬件摘要", en: "Hardware Summary"))
        \(L10n.text(zh: "供电", en: "Power")): \(snapshot.power.displayName)
        \(L10n.text(zh: "核心拓扑", en: "Core topology")): \(cpu.performanceCores.map(String.init) ?? "?")P / \(cpu.efficiencyCores.map(String.init) ?? "?")E
        \(L10n.text(zh: "E 核平均", en: "E-core average")): \(String(format: "%.0f%%", efficiencyAverage))
        \(L10n.text(zh: "P 核平均", en: "P-core average")): \(String(format: "%.0f%%", performanceAverage))
        \(L10n.text(zh: "Helper", en: "Helper")): \(snapshot.helperAvailable ? L10n.text(zh: "可用", en: "Ready") : L10n.text(zh: "未找到", en: "Missing"))
        \(L10n.text(zh: "LaunchDaemon", en: "LaunchDaemon")): \(snapshot.daemonRunning ? L10n.text(zh: "运行中", en: "Running") : L10n.text(zh: "未安装", en: "Not Installed"))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        appendOutput(L10n.text(
            zh: "已复制硬件摘要。",
            en: "Copied hardware summary."
        ))
    }

    @objc private func changeLanguageFromPopup(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue) else {
            return
        }
        AppLanguage.selected = language
    }

    private func runHelper(arguments: [String]) {
        let helper = helperPath()
        appendOutput("$ \(helper) \(arguments.joined(separator: " "))")

        DispatchQueue.global(qos: .userInitiated).async { [weak self, helper, arguments] in
            let result = AppCommandRunner.run(helper, arguments)
            DispatchQueue.main.async {
                self?.appendOutput(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
                self?.appendOutput("exit code: \(result.exitCode)")
                self?.refreshStatus()
            }
        }
    }

    private func runHelperForProcessAnalysis(arguments: [String]) {
        let helper = helperPath()
        DispatchQueue.global(qos: .userInitiated).async { [weak self, helper, arguments] in
            let result = AppCommandRunner.run(helper, arguments)
            DispatchQueue.main.async {
                self?.processAnalysisView.string = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.appendOutput("$ \(helper) \(arguments.joined(separator: " "))\nexit code: \(result.exitCode)")
                self?.refreshStatus()
            }
        }
    }

    private func currentPolicyArguments(includeTiming: Bool) -> [String] {
        var arguments: [String] = []

        if includeTiming {
            arguments.append(contentsOf: [
                "--interval",
                intervalField.stringValue,
                "--reapply-interval",
                reapplyField.stringValue
            ])
        }

        if policyEnabledToggle.state != .on {
            arguments.append("--policy-disabled")
        }

        arguments.append(contentsOf: ["--policy-mode", selectedPolicyMode.argument])

        if restoreToggle.state != .on {
            arguments.append("--no-restore-background-on-battery")
        }
        if protectSystemToggle.state != .on {
            arguments.append("--no-protect-system-critical")
        }

        let whitelist = whitelistedProcessNames()
        if !whitelist.isEmpty {
            arguments.append(contentsOf: ["--whitelist", whitelist.joined(separator: ",")])
        }

        return arguments
    }

    private func whitelistedProcessNames() -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n")
        return whitelistField.stringValue
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func runAdminCommand(_ command: String, label: String) {
        appendOutput("$ \(label)")
        appendOutput(L10n.text(
            zh: "安全提示：MACPI 不保存 macOS 管理员密码；接下来的密码弹窗由系统处理。安装完成后，状态刷新、自测、Dry Run 和进程分析不会要求密码。",
            zhHant: "安全提示：MACPI 不保存 macOS 管理員密碼；接下來的密碼彈窗由系統處理。安裝完成後，狀態刷新、自測、Dry Run 同進程分析不會要求密碼。",
            yue: "安全提示：MACPI 唔會保存 macOS 管理員密碼；之後個密碼彈窗係系統處理。安裝完成之後，狀態刷新、自測、Dry Run 同程序分析都唔使密碼。",
            en: "Security note: MACPI does not store your macOS administrator password; the upcoming password prompt is handled by the system. After installation, status refresh, self-test, Dry Run, and process analysis do not require a password."
        ))

        DispatchQueue.global(qos: .userInitiated).async { [weak self, command] in
            let encoded = Data(command.utf8).base64EncodedString()
            let shell = "/bin/echo \(encoded) | /usr/bin/base64 -D | /bin/sh"
            let script = "do shell script \"\(Self.appleScriptEscaped(shell))\" with administrator privileges"
            let result = AppCommandRunner.run("/usr/bin/osascript", ["-e", script])
            DispatchQueue.main.async {
                self?.appendOutput(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
                self?.appendOutput("exit code: \(result.exitCode)")
                self?.refreshStatus()
            }
        }
    }

    private func appendOutput(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        let current = outputView.string
        outputView.string = current.isEmpty ? text : "\(current)\n\n\(text)"
        outputView.scrollToEndOfDocument(nil)
    }

    private func helperPath() -> String {
        AppBundlePaths.helperPath()
    }

    private func validatedInteger(from text: String, minimum: Int) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              value >= minimum else {
            return nil
        }
        return value
    }

    private func launchDaemonArguments(interval: Int, reapply: Int) -> [String] {
        var arguments = [
            LaunchDaemonConstants.helperPath,
            "daemon"
        ]
        arguments.append(contentsOf: [
            "--interval",
            "\(interval)",
            "--reapply-interval",
            "\(reapply)"
        ])
        arguments.append(contentsOf: currentPolicyArguments(includeTiming: false))
        return arguments
    }

    private func launchDaemonInstallationIsCurrent(arguments: [String], helperSourcePath: String) -> Bool {
        guard AppStatusSnapshot.current().daemonRunning,
              installedHelperMatches(sourcePath: helperSourcePath),
              installedLaunchDaemonArguments() == arguments else {
            return false
        }
        return true
    }

    private func installedHelperMatches(sourcePath: String) -> Bool {
        let installedURL = URL(fileURLWithPath: LaunchDaemonConstants.helperPath)
        let sourceURL = URL(fileURLWithPath: sourcePath)
        guard let sourceData = try? Data(contentsOf: sourceURL),
              let installedData = try? Data(contentsOf: installedURL) else {
            return false
        }
        return sourceData == installedData
    }

    private func installedLaunchDaemonArguments() -> [String]? {
        let url = URL(fileURLWithPath: LaunchDaemonConstants.plistPath)
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any],
              dictionary["Label"] as? String == LaunchDaemonConstants.label,
              let arguments = dictionary["ProgramArguments"] as? [String] else {
            return nil
        }
        return arguments
    }

    private func writeStagedLaunchDaemonPlist(data: Data) throws -> String {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = cache.appendingPathComponent("MACPI", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("com.local.macpi.\(UUID().uuidString).plist")
        try data.write(to: url, options: .atomic)
        return url.path
    }

    private func uninstallShellCommand() -> String {
        let plist = ShellQuote.quote(LaunchDaemonConstants.plistPath)
        let helper = ShellQuote.quote(LaunchDaemonConstants.helperPath)
        return """
        set -e
        if /bin/launchctl print \(LaunchDaemonConstants.serviceTarget) >/dev/null 2>&1; then
          /bin/launchctl bootout system \(plist) >/dev/null 2>&1 || true
        fi
        /bin/rm -f \(plist)
        /bin/rm -f \(helper)
        """
    }

    nonisolated private static func appleScriptEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let openHandler: () -> Void
    private let quitHandler: () -> Void
    private let powerItem = NSMenuItem(title: L10n.text(zh: "供电：读取中", en: "Power: Loading"), action: nil, keyEquivalent: "")
    private let coreItem = NSMenuItem(title: L10n.text(zh: "核心：读取中", en: "Cores: Loading"), action: nil, keyEquivalent: "")
    private let helperItem = NSMenuItem(title: L10n.text(zh: "Helper：读取中", en: "Helper: Loading"), action: nil, keyEquivalent: "")
    private let daemonItem = NSMenuItem(title: L10n.text(zh: "LaunchDaemon：读取中", en: "LaunchDaemon: Loading"), action: nil, keyEquivalent: "")
    private let refreshTimer = AppTimerBox()

    init(openHandler: @escaping () -> Void, quitHandler: @escaping () -> Void) {
        self.openHandler = openHandler
        self.quitHandler = quitHandler
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .appLanguageDidChange,
            object: nil
        )
        setupMenu()
        refreshStatus()
        startTimer()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        refreshTimer.invalidate()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatus()
    }

    private func setupMenu() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "MACPI")
            button.image?.isTemplate = true
            button.toolTip = "MACPI"
        }

        let menu = NSMenu()
        menu.delegate = self

        let openItem = NSMenuItem(title: L10n.text(zh: "打开 MACPI", en: "Open MACPI"), action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        let refreshItem = NSMenuItem(title: L10n.text(zh: "刷新状态", en: "Refresh Status"), action: #selector(refreshStatus), keyEquivalent: "")
        refreshItem.target = self
        let quitItem = NSMenuItem(title: L10n.text(zh: "退出 MACPI", en: "Quit MACPI"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        let languageItem = NSMenuItem(title: L10n.text(zh: "语言", en: "Language"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        AppLanguage.allCases.forEach { language in
            let item = NSMenuItem(title: language.menuTitle, action: #selector(changeLanguage), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = language == AppLanguage.selected ? .on : .off
            languageMenu.addItem(item)
        }
        menu.setSubmenu(languageMenu, for: languageItem)

        [powerItem, coreItem, helperItem, daemonItem].forEach { item in
            item.isEnabled = false
        }

        menu.addItem(openItem)
        menu.addItem(refreshItem)
        menu.addItem(languageItem)
        menu.addItem(.separator())
        menu.addItem(powerItem)
        menu.addItem(coreItem)
        menu.addItem(helperItem)
        menu.addItem(daemonItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func startTimer() {
        let timer = Timer(
            timeInterval: 5,
            target: self,
            selector: #selector(refreshStatus),
            userInfo: nil,
            repeats: true
        )
        refreshTimer.replace(with: timer)
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func openApp() {
        openHandler()
    }

    @objc private func quitApp() {
        quitHandler()
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue) else {
            return
        }
        AppLanguage.selected = language
    }

    @objc private func languageDidChange() {
        setupMenu()
        refreshStatus()
    }

    @objc private func refreshStatus() {
        DispatchQueue.global(qos: .utility).async {
            let snapshot = AppStatusSnapshot.current()
            DispatchQueue.main.async { [weak self] in
                self?.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: AppStatusSnapshot) {
        let coreText = "\(snapshot.cpu.performanceCores.map(String.init) ?? "?")P / \(snapshot.cpu.efficiencyCores.map(String.init) ?? "?")E"
        powerItem.title = L10n.text(zh: "供电：\(snapshot.power.displayName)", en: "Power: \(snapshot.power.displayName)")
        coreItem.title = L10n.text(zh: "核心：\(coreText)", en: "Cores: \(coreText)")
        helperItem.title = L10n.text(
            zh: "Helper：\(snapshot.helperAvailable ? L10n.text(zh: "可用", en: "Ready") : L10n.text(zh: "未找到", en: "Missing"))",
            en: "Helper: \(snapshot.helperAvailable ? L10n.text(zh: "可用", en: "Ready") : L10n.text(zh: "未找到", en: "Missing"))"
        )
        daemonItem.title = L10n.text(
            zh: "LaunchDaemon：\(snapshot.daemonRunning ? L10n.text(zh: "运行中", en: "Running") : L10n.text(zh: "未安装", en: "Not Installed"))",
            en: "LaunchDaemon: \(snapshot.daemonRunning ? L10n.text(zh: "运行中", en: "Running") : L10n.text(zh: "未安装", en: "Not Installed"))"
        )
        statusItem.button?.toolTip = "MACPI · \(snapshot.power.displayName) · \(snapshot.daemonRunning ? L10n.text(zh: "服务运行中", en: "Service Running") : L10n.text(zh: "服务未安装", en: "Service Missing"))"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if statusBarController == nil {
            statusBarController = StatusBarController(
                openHandler: { [weak self] in
                    self?.showMainWindow()
                    NSApp.activate(ignoringOtherApps: true)
                },
                quitHandler: {
                    NSApp.terminate(nil)
                }
            )
        }
        showMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func showMainWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let controller = DashboardViewController()
        let window = NSWindow(contentViewController: controller)
        window.title = "MACPI"
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: AppLayout.windowWidth, height: AppLayout.windowHeight))
        window.minSize = NSSize(width: AppLayout.windowMinWidth, height: AppLayout.windowMinHeight)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }
}

let appDelegate = AppDelegate()
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.delegate = appDelegate
appDelegate.showMainWindow()
app.activate(ignoringOtherApps: true)
app.run()
