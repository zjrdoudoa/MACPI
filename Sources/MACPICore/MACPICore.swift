import Darwin
import Dispatch
import Foundation
import IOKit.ps

extension String {
    func ifEmpty(_ replacement: String) -> String {
        isEmpty ? replacement : self
    }
}

enum MACPIError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case commandFailed(String)

    var description: String {
        switch self {
        case .invalidArgument(let message):
            return message
        case .commandFailed(let message):
            return message
        }
    }
}

enum PowerState: String {
    case ac = "AC Power"
    case battery = "Battery Power"
    case unknown = "Unknown"
}

enum BatteryLowPowerMode: String {
    case on
    case off
    case unchanged
}

enum PolicyMode: String {
    case balanced
    case performance
    case aggressive
}

struct MACPIConfig {
    var interval: TimeInterval = 15
    var reapplyInterval: TimeInterval = 60
    var policyEnabled = true
    var policyMode: PolicyMode = .balanced
    var dryRun = false
    var aggressiveRenice = false
    var managePowerSettings = false
    var restoreBackgroundOnBattery = true
    var batteryLowPowerMode: BatteryLowPowerMode = .unchanged
    var protectSystemCritical = true
    var includeSystemProcesses = false
    var onlyPIDs: Set<pid_t> = []
    var whitelistedProcessNames: Set<String> = Self.defaultWhitelistedProcessNames
    var excludedProcessNames: Set<String> = Self.defaultExcludedProcessNames

    static let defaultWhitelistedProcessNames: Set<String> = [
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

    static let defaultExcludedProcessNames: Set<String> = [
        "kernel_task",
        "taskpolicy",
        "renice",
        "macpi"
    ]

    static let systemCriticalProcessNames: Set<String> = [
        "WindowServer",
        "airportd",
        "analyticsd",
        "bluetoothd",
        "cfprefsd",
        "configd",
        "coreaudiod",
        "distnoted",
        "diskarbitrationd",
        "kernelmanagerd",
        "launchd",
        "locationd",
        "loginwindow",
        "logd",
        "mDNSResponder",
        "notifyd",
        "powerd",
        "runningboardd",
        "securityd",
        "syslogd",
        "thermalmonitord",
        "trustd",
        "watchdogd"
    ]
}

struct CommandResult {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String

    var succeeded: Bool {
        exitCode == 0
    }

    var trimmedOutput: String {
        let text = [standardOutput, standardError]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CommandRunner {
    static func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: String(data: outputData, encoding: .utf8) ?? "",
            standardError: ""
        )
    }
}

struct SyscallFailure: Error, CustomStringConvertible {
    let operation: String
    let code: Int32

    var description: String {
        "\(operation) failed errno=\(code) \(String(cString: strerror(code)))"
    }
}

struct ProcessIdentity: Hashable, CustomStringConvertible {
    let pid: pid_t
    let startSec: UInt64
    let startUsec: UInt64

    var description: String {
        "pid=\(pid) start=\(startSec).\(startUsec)"
    }
}

enum ProcessIdentityFactory {
    static func identity(pid: pid_t, info: proc_bsdinfo, returnedLength: Int32) -> ProcessIdentity? {
        guard returnedLength == Int32(MemoryLayout<proc_bsdinfo>.size) else {
            return nil
        }
        return ProcessIdentity(pid: pid, startSec: info.pbi_start_tvsec, startUsec: info.pbi_start_tvusec)
    }
}

struct DarwinScheduler {
    static func bsdInfo(pid: pid_t) -> Result<proc_bsdinfo, SyscallFailure> {
        var info = proc_bsdinfo()
        errno = 0
        let expectedLength = Int32(MemoryLayout<proc_bsdinfo>.size)
        let length = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, expectedLength)
        }
        guard length == expectedLength else {
            let code = errno == 0 ? ESRCH : errno
            return .failure(SyscallFailure(operation: "proc_pidinfo(PROC_PIDTBSDINFO,size=\(length),expected=\(expectedLength))", code: code))
        }
        return .success(info)
    }

    /// ProcessIdentity uses PID + BSD start time to avoid reusing cached policy state
    /// across PID reuse. This is not a kernel unique ID; if it cannot be read exactly,
    /// MACPI treats the process identity as unknown and avoids stateful restore/cache use.
    static func identity(pid: pid_t) -> Result<ProcessIdentity, SyscallFailure> {
        switch bsdInfo(pid: pid) {
        case .success(let info):
            guard let identity = ProcessIdentityFactory.identity(
                pid: pid,
                info: info,
                returnedLength: Int32(MemoryLayout<proc_bsdinfo>.size)
            ) else {
                return .failure(SyscallFailure(operation: "ProcessIdentityFactory", code: ESRCH))
            }
            return .success(identity)
        case .failure(let failure):
            return .failure(failure)
        }
    }

    static func isDarwinBackground(pid: pid_t) -> Result<Bool, SyscallFailure> {
        let info: proc_bsdinfo
        switch bsdInfo(pid: pid) {
        case .success(let bsdInfo):
            info = bsdInfo
        case .failure(let failure):
            return .failure(failure)
        }

        let backgroundFlags = UInt32(PROC_FLAG_DARWINBG | PROC_FLAG_EXT_DARWINBG)
        return .success((info.pbi_flags & backgroundFlags) != 0)
    }

    static func clearBackgroundPolicy(pid: pid_t) -> SyscallFailure? {
        errno = 0
        let result = setpriority(PRIO_DARWIN_PROCESS, UInt32(pid), 0)
        guard result != 0 else {
            return nil
        }
        return SyscallFailure(operation: "setpriority(PRIO_DARWIN_PROCESS)", code: errno)
    }

    static func restoreBackgroundPolicy(pid: pid_t) -> SyscallFailure? {
        errno = 0
        let result = setpriority(PRIO_DARWIN_PROCESS, UInt32(pid), PRIO_DARWIN_BG)
        guard result != 0 else {
            return nil
        }
        return SyscallFailure(operation: "setpriority(PRIO_DARWIN_PROCESS,PRIO_DARWIN_BG)", code: errno)
    }

    static func renice(pid: pid_t, priority: Int32) -> SyscallFailure? {
        errno = 0
        let result = setpriority(PRIO_PROCESS, UInt32(pid), priority)
        guard result != 0 else {
            return nil
        }
        return SyscallFailure(operation: "setpriority(PRIO_PROCESS,\(priority))", code: errno)
    }

    static func currentNice(pid: pid_t) -> Result<Int32, SyscallFailure> {
        errno = 0
        let value = getpriority(PRIO_PROCESS, UInt32(pid))
        if value == -1, errno != 0 {
            return .failure(SyscallFailure(operation: "getpriority(PRIO_PROCESS)", code: errno))
        }
        return .success(Int32(value))
    }
}

struct Logger {
    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    static func info(_ message: String) {
        write("INFO", message)
    }

    static func warn(_ message: String) {
        write("WARN", message)
    }

    static func error(_ message: String) {
        write("ERROR", message)
    }

    private static func write(_ level: String, _ message: String) {
        print("\(timestamp()) [\(level)] \(message)")
        fflush(stdout)
    }
}

struct PowerSource {
    static func current() -> PowerState {
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

struct SystemProcess {
    let pid: pid_t
    let command: String
    let name: String
    let uid: uid_t
    let identity: ProcessIdentity?
    let isDarwinBackground: Bool?

    var processName: String {
        if !name.isEmpty {
            return name
        }
        return URL(fileURLWithPath: command).lastPathComponent
    }
}

struct ProcessEnumerator {
    static func allProcesses() throws -> [SystemProcess] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else {
            throw MACPIError.commandFailed("proc_listpids failed while sizing pid buffer")
        }

        let pidSize = MemoryLayout<pid_t>.stride
        let capacity = Int(byteCount) / pidSize + 128
        var pids = [pid_t](repeating: 0, count: capacity)
        let returnedBytes = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard returnedBytes > 0 else {
            throw MACPIError.commandFailed("proc_listpids failed while reading pid buffer")
        }

        let count = min(Int(returnedBytes) / pidSize, pids.count)
        return pids.prefix(count).compactMap { pid in
            guard pid > 0 else {
                return nil
            }
            let bsdInfo = DarwinScheduler.bsdInfo(pid: pid)
            let uid: uid_t
            let identity: ProcessIdentity?
            let isBackground: Bool?
            switch bsdInfo {
            case .success(let info):
                uid = info.pbi_uid
                identity = ProcessIdentity(
                    pid: pid,
                    startSec: info.pbi_start_tvsec,
                    startUsec: info.pbi_start_tvusec
                )
                let backgroundFlags = UInt32(PROC_FLAG_DARWINBG | PROC_FLAG_EXT_DARWINBG)
                isBackground = (info.pbi_flags & backgroundFlags) != 0
            case .failure:
                uid = uid_t.max
                identity = nil
                isBackground = nil
            }
            return SystemProcess(
                pid: pid,
                command: processPath(pid: pid),
                name: processName(pid: pid),
                uid: uid,
                identity: identity,
                isDarwinBackground: isBackground
            )
        }
    }

    private static func processPath(pid: pid_t) -> String {
        let capacity = 4096
        var buffer = [CChar](repeating: 0, count: capacity)
        let length = buffer.withUnsafeMutableBufferPointer { pointer in
            proc_pidpath(pid, pointer.baseAddress, UInt32(capacity))
        }
        guard length > 0 else {
            return ""
        }
        return decodeNullTerminated(buffer)
    }

    private static func processName(pid: pid_t) -> String {
        let capacity = 256
        var buffer = [CChar](repeating: 0, count: capacity)
        let length = buffer.withUnsafeMutableBufferPointer { pointer in
            proc_name(pid, pointer.baseAddress, UInt32(capacity))
        }
        guard length > 0 else {
            return ""
        }
        return decodeNullTerminated(buffer)
    }

    private static func decodeNullTerminated(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

struct CPUInfo {
    let performanceCoreCount: Int?
    let efficiencyCoreCount: Int?
    let performanceLevelName: String?
    let efficiencyLevelName: String?

    static func current() -> CPUInfo {
        CPUInfo(
            performanceCoreCount: sysctlInt("hw.perflevel0.physicalcpu"),
            efficiencyCoreCount: sysctlInt("hw.perflevel1.physicalcpu"),
            performanceLevelName: sysctlString("hw.perflevel0.name"),
            efficiencyLevelName: sysctlString("hw.perflevel1.name")
        )
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let status = sysctlbyname(name, &value, &size, nil, 0)
        return status == 0 ? Int(value) : nil
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

struct PolicySummary {
    var scanned = 0
    var boosted = 0
    var restored = 0
    var reniced = 0
    var cached = 0
    var skipped = 0
    var failed = 0
    var failureSamples: [String] = []

    mutating func recordFailure(_ message: String) {
        failed += 1
        if failureSamples.count < 8 {
            failureSamples.append(message)
        }
    }
}

struct TrackedProcessState {
    let identity: ProcessIdentity
    let pid: pid_t
    let name: String

    var originalBackground: Bool?
    var originalNice: Int32?
    var changedBackgroundByMACPI = false
    var changedNiceByMACPI = false
    var lastBoostAt: Date?
    var lastReniceAt: Date?
}

final class ProcessStateTracker {
    private var states: [ProcessIdentity: TrackedProcessState] = [:]

    var count: Int {
        states.count
    }

    var allStates: [TrackedProcessState] {
        Array(states.values)
    }

    func state(for process: SystemProcess) -> TrackedProcessState? {
        guard let identity = process.identity else {
            return nil
        }
        if let state = states[identity] {
            return state
        }
        return TrackedProcessState(identity: identity, pid: process.pid, name: process.processName)
    }

    func update(_ state: TrackedProcessState) {
        states[state.identity] = state
    }

    func prune(liveIdentities: Set<ProcessIdentity>) {
        states = states.filter { liveIdentities.contains($0.key) }
    }

    func clear() {
        states.removeAll(keepingCapacity: false)
    }
}

final class PolicyEngine {
    let config: MACPIConfig
    private let tracker = ProcessStateTracker()

    init(config: MACPIConfig) {
        self.config = config
    }

    func applyACPolicy(includePowerSettings: Bool = true, forceReapply: Bool = false) {
        guard config.policyEnabled else {
            Logger.info("policy disabled, restoring modified processes")
            restoreModifiedProcesses(reason: "policy disabled")
            clearSessionState()
            return
        }

        if includePowerSettings, config.managePowerSettings {
            applyACPowerSettings()
        }

        do {
            var summary = PolicySummary()
            let processes = try ProcessEnumerator.allProcesses()
            let now = Date()
            pruneCache(processes: processes)

            for process in processes {
                summary.scanned += 1

                guard shouldTouch(process) else {
                    summary.skipped += 1
                    continue
                }

                guard let identity = process.identity else {
                    summary.skipped += 1
                    continue
                }

                if config.policyMode == .balanced, process.isDarwinBackground != true {
                    summary.skipped += 1
                    continue
                }

                let state = tracker.state(for: process)
                let shouldReapplyBoost = shouldReapply(lastApplied: state?.lastBoostAt, now: now) || forceReapply
                if shouldReapplyBoost {
                    applyTaskPolicyBoost(to: process, identity: identity, at: now, summary: &summary)
                } else {
                    summary.cached += 1
                }

                if shouldRenice {
                    let refreshedState = tracker.state(for: process)
                    let shouldReapplyRenice = shouldReapply(lastApplied: refreshedState?.lastReniceAt, now: now) || forceReapply
                    if shouldReapplyRenice {
                        applyReniceBoost(to: process, identity: identity, at: now, summary: &summary)
                    }
                }
            }

            Logger.info("AC performance pass scanned=\(summary.scanned) boosted=\(summary.boosted) cached=\(summary.cached) reniced=\(summary.reniced) skipped=\(summary.skipped) failed=\(summary.failed)")
            for sample in summary.failureSamples {
                Logger.warn(sample)
            }
        } catch {
            Logger.error("Failed to enumerate processes: \(error)")
        }
    }

    func applyBatteryPolicy() {
        guard config.policyEnabled else {
            Logger.info("policy disabled, restoring modified processes")
            restoreModifiedProcesses(reason: "policy disabled")
            clearSessionState()
            return
        }

        if config.managePowerSettings {
            applyBatteryPowerSettings()
        }
        restoreModifiedProcesses(
            reason: "battery policy",
            includeBackground: config.restoreBackgroundOnBattery,
            includeNice: true
        )
        clearSessionState()
    }

    private var shouldRenice: Bool {
        config.policyMode == .aggressive
    }

    private func shouldTouch(_ process: SystemProcess) -> Bool {
        if !config.onlyPIDs.isEmpty, !config.onlyPIDs.contains(process.pid) {
            return false
        }
        guard process.pid > 1 else {
            return false
        }
        guard process.pid != getpid() else {
            return false
        }
        if !config.includeSystemProcesses, !isUserProcess(process) {
            return false
        }
        guard !config.whitelistedProcessNames.contains(process.processName) else {
            return false
        }
        guard !config.excludedProcessNames.contains(process.processName) else {
            return false
        }
        if config.protectSystemCritical,
           MACPIConfig.systemCriticalProcessNames.contains(process.processName) {
            return false
        }
        return true
    }

    private func isUserProcess(_ process: SystemProcess) -> Bool {
        process.uid == getuid() || (process.uid >= 500 && process.uid != uid_t.max)
    }

    private func shouldReapply(lastApplied: Date?, now: Date) -> Bool {
        guard let lastApplied else {
            return true
        }
        return now.timeIntervalSince(lastApplied) >= config.reapplyInterval
    }

    private func pruneCache(processes: [SystemProcess]) {
        tracker.prune(liveIdentities: Set(processes.compactMap(\.identity)))
    }

    private func applyTaskPolicyBoost(to process: SystemProcess, identity: ProcessIdentity, at date: Date, summary: inout PolicySummary) {
        if config.dryRun {
            Logger.info("dry-run would clear background policy pid=\(process.pid) name=\(process.processName)")
            summary.boosted += 1
            return
        }

        var state = tracker.state(for: process) ?? TrackedProcessState(identity: identity, pid: process.pid, name: process.processName)
        if state.originalBackground == nil {
            state.originalBackground = process.isDarwinBackground
        }

        if let failure = DarwinScheduler.clearBackgroundPolicy(pid: process.pid) {
            applyTaskPolicyFallback(to: process, state: &state, at: date, nativeFailure: failure, summary: &summary)
            return
        }

        if state.originalBackground == true {
            state.changedBackgroundByMACPI = true
        }
        state.lastBoostAt = date
        tracker.update(state)
        summary.boosted += 1
    }

    func restoreModifiedProcesses(reason: String, timeout: TimeInterval? = nil, includeBackground: Bool = true, includeNice: Bool = true) {
        let started = Date()
        let deadline = timeout.map { started.addingTimeInterval($0) }
        var summary = PolicySummary(scanned: tracker.count)

        for state in tracker.allStates {
            if let deadline, Date() >= deadline {
                Logger.warn("restore timeout reason=\(reason) after \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
                break
            }

            switch DarwinScheduler.identity(pid: state.pid) {
            case .success(let currentIdentity):
                guard currentIdentity == state.identity else {
                    summary.recordFailure("restore skipped identity mismatch cached=\(state.identity) current=\(currentIdentity) name=\(state.name)")
                    continue
                }
            case .failure(let failure):
                summary.recordFailure("restore skipped identity unavailable pid=\(state.pid) name=\(state.name): \(failure)")
                continue
            }

            if includeBackground, state.changedBackgroundByMACPI, state.originalBackground == true {
                if config.dryRun {
                    Logger.info("dry-run would restore background pid=\(state.pid) name=\(state.name) reason=\(reason)")
                    summary.restored += 1
                } else if let failure = DarwinScheduler.restoreBackgroundPolicy(pid: state.pid) {
                    summary.recordFailure("restore background failed pid=\(state.pid) name=\(state.name): \(failure)")
                } else {
                    summary.restored += 1
                }
            }

            if includeNice, state.changedNiceByMACPI, let originalNice = state.originalNice {
                if config.dryRun {
                    Logger.info("dry-run would restore nice pid=\(state.pid) name=\(state.name) nice=\(originalNice) reason=\(reason)")
                    summary.restored += 1
                } else if let failure = DarwinScheduler.renice(pid: state.pid, priority: originalNice) {
                    summary.recordFailure("restore nice failed pid=\(state.pid) name=\(state.name) nice=\(originalNice): \(failure)")
                } else {
                    summary.restored += 1
                }
            }
        }

        Logger.info("restore modified processes reason=\(reason) scanned=\(summary.scanned) restored=\(summary.restored) failed=\(summary.failed)")
        for sample in summary.failureSamples {
            Logger.warn(sample)
        }
    }

    private func clearSessionState() {
        tracker.clear()
    }

    private func applyTaskPolicyFallback(to process: SystemProcess, state: inout TrackedProcessState, at date: Date, nativeFailure: SyscallFailure, summary: inout PolicySummary) {
        do {
            let result = try CommandRunner.run("/usr/sbin/taskpolicy", ["-B", "-p", "\(process.pid)"])
            if result.succeeded {
                summary.boosted += 1
                if state.originalBackground == true {
                    state.changedBackgroundByMACPI = true
                }
                state.lastBoostAt = date
                tracker.update(state)
            } else {
                summary.recordFailure("boost failed pid=\(process.pid) name=\(process.processName): \(nativeFailure); taskpolicy fallback: \(result.trimmedOutput)")
            }
        } catch {
            summary.recordFailure("boost failed pid=\(process.pid) name=\(process.processName): \(nativeFailure); taskpolicy launch failed: \(error)")
        }
    }

    private func applyReniceBoost(to process: SystemProcess, identity: ProcessIdentity, at date: Date, summary: inout PolicySummary) {
        if config.dryRun {
            Logger.info("dry-run would renice pid=\(process.pid) name=\(process.processName) nice=-5")
            summary.reniced += 1
            return
        }

        var state = tracker.state(for: process) ?? TrackedProcessState(identity: identity, pid: process.pid, name: process.processName)
        if state.originalNice == nil {
            switch DarwinScheduler.currentNice(pid: process.pid) {
            case .success(let nice):
                state.originalNice = nice
            case .failure(let failure):
                summary.recordFailure("renice skipped; could not read original nice pid=\(process.pid) name=\(process.processName): \(failure)")
                return
            }
        }

        if let failure = DarwinScheduler.renice(pid: process.pid, priority: -5) {
            applyReniceFallback(to: process, state: &state, at: date, nativeFailure: failure, summary: &summary)
            return
        }

        state.changedNiceByMACPI = true
        state.lastReniceAt = date
        tracker.update(state)
        summary.reniced += 1
    }

    private func applyReniceFallback(to process: SystemProcess, state: inout TrackedProcessState, at date: Date, nativeFailure: SyscallFailure, summary: inout PolicySummary) {
        do {
            let result = try CommandRunner.run("/usr/bin/renice", ["-n", "-5", "-p", "\(process.pid)"])
            if result.succeeded {
                summary.reniced += 1
                state.changedNiceByMACPI = true
                state.lastReniceAt = date
                tracker.update(state)
            } else {
                summary.recordFailure("renice failed pid=\(process.pid) name=\(process.processName): \(nativeFailure); renice fallback: \(result.trimmedOutput)")
            }
        } catch {
            summary.recordFailure("renice failed pid=\(process.pid) name=\(process.processName): \(nativeFailure); renice launch failed: \(error)")
        }
    }

    private func applyACPowerSettings() {
        Logger.info("AC power mode settings left unchanged")
    }

    private func applyBatteryPowerSettings() {
        switch config.batteryLowPowerMode {
        case .on:
            runPMSet(["-b", "lowpowermode", "1"], description: "enable Low Power Mode on battery")
        case .off:
            runPMSet(["-b", "lowpowermode", "0"], description: "disable Low Power Mode on battery")
        case .unchanged:
            Logger.info("Battery Low Power Mode left unchanged")
        }
    }

    private func runPMSet(_ arguments: [String], description: String) {
        if config.dryRun {
            Logger.info("dry-run pmset \(arguments.joined(separator: " ")) # \(description)")
            return
        }

        do {
            let result = try CommandRunner.run("/usr/bin/pmset", arguments)
            if result.succeeded {
                Logger.info("pmset ok: \(description)")
            } else {
                Logger.warn("pmset unsupported or failed for \(description): \(result.trimmedOutput)")
            }
        } catch {
            Logger.warn("pmset launch failed for \(description): \(error)")
        }
    }
}

final class PowerAwareDaemon: @unchecked Sendable {
    private let config: MACPIConfig
    private let engine: PolicyEngine
    private var lastState: PowerState?
    private var notificationSource: CFRunLoopSource?
    private var timer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var isShuttingDown = false

    init(config: MACPIConfig) {
        self.config = config
        self.engine = PolicyEngine(config: config)
    }

    func start() {
        Logger.info("MACPI daemon started enabled=\(config.policyEnabled) mode=\(config.policyMode.rawValue) interval=\(Int(config.interval))s reapplyInterval=\(Int(config.reapplyInterval))s dryRun=\(config.dryRun) protectSystemCritical=\(config.protectSystemCritical) whitelist=\(config.whitelistedProcessNames.sorted().joined(separator: ",").ifEmpty("none"))")

        installShutdownSignalSources()
        installPowerNotification()
        installProcessScanTimer()
        evaluatePowerState(reason: "startup", scanProcessesOnAC: true)
        CFRunLoopRun()
    }

    private func installShutdownSignalSources() {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        signalSources = [SIGTERM, SIGINT].map { signalNumber in
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.handleShutdownSignal(signalNumber)
            }
            source.resume()
            return source
        }
        Logger.info("Shutdown signal sources installed")
    }

    private func handleShutdownSignal(_ signalNumber: Int32) {
        guard !isShuttingDown else {
            return
        }
        isShuttingDown = true
        Logger.info("Received signal \(signalNumber); restoring modified processes before shutdown")
        timer?.invalidate()
        restoreAndStopRunLoop(reason: "daemon shutdown")
    }

    private func restoreAndStopRunLoop(reason: String) {
        engine.restoreModifiedProcesses(reason: reason, timeout: 4)
        CFRunLoopStop(CFRunLoopGetMain())
    }

    private func installPowerNotification() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else {
                return
            }
            let daemon = Unmanaged<PowerAwareDaemon>.fromOpaque(context).takeUnretainedValue()
            daemon.evaluatePowerState(reason: "power-notification", scanProcessesOnAC: false)
        }, context)?.takeRetainedValue() else {
            Logger.warn("Unable to install IOKit power-source notification; falling back to interval scanning")
            return
        }

        notificationSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        Logger.info("IOKit power-source notification installed")
    }

    private func installProcessScanTimer() {
        let scanTimer = Timer(timeInterval: config.interval, repeats: true) { [weak self] _ in
            self?.evaluatePowerState(reason: "interval-scan", scanProcessesOnAC: true)
        }
        timer = scanTimer
        RunLoop.current.add(scanTimer, forMode: .common)
    }

    private func evaluatePowerState(reason: String, scanProcessesOnAC: Bool) {
        autoreleasepool {
            let state = PowerSource.current()
            let stateChanged = state != lastState

            if stateChanged {
                Logger.info("Power source changed: \(lastState?.rawValue ?? "none") -> \(state.rawValue) reason=\(reason)")
                lastState = state
            }

            switch state {
            case .ac:
                if stateChanged || scanProcessesOnAC {
                    engine.applyACPolicy(includePowerSettings: stateChanged, forceReapply: stateChanged)
                }
            case .battery:
                if stateChanged {
                    engine.applyBatteryPolicy()
                }
            case .unknown:
                if stateChanged {
                    Logger.warn("Power source unknown; leaving process policy unchanged")
                }
            }
        }
    }
}

struct CLI {
    static func run(arguments: [String]) throws {
        var remaining = Array(arguments.dropFirst())
        let command = remaining.first.flatMap(Command.init(rawValue:)) ?? .help
        if command != .help {
            remaining.removeFirst()
        }

        switch command {
        case .daemon:
            let config = try parseConfig(from: remaining, validateConflicts: true)
            try warnIfNotRoot(config: config)
            runDaemon(config: config)
        case .once:
            let config = try parseConfig(from: remaining, validateConflicts: true)
            try warnIfNotRoot(config: config)
            runOnce(config: config)
        case .analyze:
            let request = try parseAnalyzeConfig(from: remaining)
            runAnalyze(config: request.config, limit: request.limit)
        case .status:
            printStatus()
        case .selfTest:
            try runSelfTest()
        case .help:
            printUsage()
        }
    }

    private enum Command: String {
        case daemon
        case once
        case analyze
        case status
        case selfTest = "self-test"
        case help
    }

    private struct AnalyzeRequest {
        var config: MACPIConfig
        var limit: Int
    }

    static func parseConfig(from arguments: [String], validateConflicts: Bool = true) throws -> MACPIConfig {
        var config = MACPIConfig()
        var index = 0
        var policyDisabledSeen = false
        var policyEnabledTrueSeen = false
        var policyEnabledFalseSeen = false
        var policyModeSeen: PolicyMode?
        var aggressiveReniceSeen = false
        var includeSystemProcessesSeen = false
        var noPowerSettingsSeen = false
        var batteryLowPowerSeen: BatteryLowPowerMode?

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--interval":
                index += 1
                guard index < arguments.count,
                      let interval = TimeInterval(arguments[index]),
                      interval >= 3 else {
                    throw MACPIError.invalidArgument("--interval requires a number >= 3")
                }
                config.interval = interval
            case "--reapply-interval":
                index += 1
                guard index < arguments.count,
                      let interval = TimeInterval(arguments[index]),
                      interval >= 3 else {
                    throw MACPIError.invalidArgument("--reapply-interval requires a number >= 3")
                }
                config.reapplyInterval = interval
            case "--policy-disabled":
                policyDisabledSeen = true
            case "--policy-enabled":
                index += 1
                guard index < arguments.count,
                      let enabled = parseBool(arguments[index]) else {
                    throw MACPIError.invalidArgument("--policy-enabled requires true or false")
                }
                if enabled {
                    policyEnabledTrueSeen = true
                } else {
                    policyEnabledFalseSeen = true
                }
            case "--policy-mode":
                index += 1
                guard index < arguments.count,
                      let mode = PolicyMode(rawValue: arguments[index]) else {
                    throw MACPIError.invalidArgument("--policy-mode requires balanced, performance, or aggressive")
                }
                if let policyModeSeen, policyModeSeen != mode {
                    throw MACPIError.invalidArgument("--policy-mode specified with conflicting values: \(policyModeSeen.rawValue) and \(mode.rawValue)")
                }
                policyModeSeen = mode
                config.policyMode = mode
            case "--dry-run":
                config.dryRun = true
            case "--aggressive-renice":
                aggressiveReniceSeen = true
            case "--no-power-settings":
                noPowerSettingsSeen = true
                config.managePowerSettings = false
            case "--no-restore-background-on-battery":
                config.restoreBackgroundOnBattery = false
            case "--no-protect-system-critical":
                config.protectSystemCritical = false
            case "--include-system-processes":
                includeSystemProcessesSeen = true
                config.includeSystemProcesses = true
            case "--battery-low-power":
                index += 1
                guard index < arguments.count,
                      let mode = BatteryLowPowerMode(rawValue: arguments[index]) else {
                    throw MACPIError.invalidArgument("--battery-low-power requires on, off, or unchanged")
                }
                batteryLowPowerSeen = mode
                config.managePowerSettings = mode != .unchanged
                config.batteryLowPowerMode = mode
            case "--exclude":
                index += 1
                guard index < arguments.count else {
                    throw MACPIError.invalidArgument("--exclude requires a process name")
                }
                config.excludedProcessNames.insert(arguments[index])
            case "--whitelist", "--allowlist":
                index += 1
                guard index < arguments.count else {
                    throw MACPIError.invalidArgument("\(argument) requires one or more process names")
                }
                config.whitelistedProcessNames.formUnion(parseProcessNameList(arguments[index]))
            case "--only-pid":
                index += 1
                guard index < arguments.count,
                      let pid = pid_t(arguments[index]),
                      pid > 0 else {
                    throw MACPIError.invalidArgument("--only-pid requires a positive PID")
                }
                config.onlyPIDs.insert(pid)
            default:
                throw MACPIError.invalidArgument("Unknown option: \(argument)")
            }
            index += 1
        }

        if let mode = policyModeSeen {
            config.policyMode = mode
        }
        if aggressiveReniceSeen {
            if let policyModeSeen, policyModeSeen != .aggressive {
                throw MACPIError.invalidArgument("--aggressive-renice conflicts with --policy-mode \(policyModeSeen.rawValue)")
            }
            config.policyMode = .aggressive
            config.aggressiveRenice = true
        }
        if policyDisabledSeen || policyEnabledFalseSeen {
            config.policyEnabled = false
        }
        if policyEnabledTrueSeen {
            config.policyEnabled = true
        }

        if validateConflicts {
            let disabledRequested = policyDisabledSeen || policyEnabledFalseSeen
            if policyDisabledSeen, policyEnabledTrueSeen {
                throw MACPIError.invalidArgument("--policy-disabled conflicts with --policy-enabled true")
            }
            if policyEnabledFalseSeen, policyEnabledTrueSeen {
                throw MACPIError.invalidArgument("--policy-enabled false conflicts with --policy-enabled true")
            }
            if disabledRequested, policyModeSeen != nil {
                throw MACPIError.invalidArgument("--policy-disabled conflicts with --policy-mode because disabled policy cannot apply a mode")
            }
            if disabledRequested, aggressiveReniceSeen {
                throw MACPIError.invalidArgument("--policy-disabled conflicts with --aggressive-renice")
            }
            if disabledRequested, includeSystemProcessesSeen {
                throw MACPIError.invalidArgument("--policy-disabled conflicts with --include-system-processes")
            }
            if disabledRequested, let batteryLowPowerSeen, batteryLowPowerSeen != .unchanged {
                throw MACPIError.invalidArgument("--policy-disabled conflicts with --battery-low-power \(batteryLowPowerSeen.rawValue)")
            }
            if noPowerSettingsSeen, let batteryLowPowerSeen, batteryLowPowerSeen != .unchanged {
                throw MACPIError.invalidArgument("--no-power-settings conflicts with --battery-low-power \(batteryLowPowerSeen.rawValue)")
            }
        }

        return config
    }

    private static func parseAnalyzeConfig(from arguments: [String]) throws -> AnalyzeRequest {
        var filtered: [String] = []
        var limit = 40
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--limit":
                index += 1
                guard index < arguments.count,
                      let value = Int(arguments[index]),
                      value > 0 else {
                    throw MACPIError.invalidArgument("--limit requires a positive integer")
                }
                limit = value
            default:
                filtered.append(argument)
                if optionRequiresValue(argument), index + 1 < arguments.count {
                    index += 1
                    filtered.append(arguments[index])
                }
            }
            index += 1
        }

        return AnalyzeRequest(config: try parseConfig(from: filtered, validateConflicts: false), limit: limit)
    }

    private static func optionRequiresValue(_ argument: String) -> Bool {
        [
            "--interval",
            "--reapply-interval",
            "--policy-enabled",
            "--policy-mode",
            "--battery-low-power",
            "--exclude",
            "--whitelist",
            "--allowlist",
            "--only-pid"
        ].contains(argument)
    }

    private static func parseBool(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    private static func parseProcessNameList(_ text: String) -> Set<String> {
        let separators = CharacterSet(charactersIn: ",;\n")
        return Set(text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    private static func warnIfNotRoot(config: MACPIConfig) throws {
        guard geteuid() != 0, !config.dryRun else {
            return
        }

        Logger.warn("Not running as root. Many system processes cannot be changed. Use sudo or install the LaunchDaemon for full effect.")
    }

    private static func runDaemon(config: MACPIConfig) {
        PowerAwareDaemon(config: config).start()
    }

    private static func runOnce(config: MACPIConfig) {
        let state = PowerSource.current()
        let engine = PolicyEngine(config: config)
        Logger.info("Current power source: \(state.rawValue)")

        switch state {
        case .ac:
            engine.applyACPolicy()
        case .battery:
            engine.applyBatteryPolicy()
        case .unknown:
            Logger.warn("Power source unknown; no process policy applied")
        }
    }

    private static func runAnalyze(config: MACPIConfig, limit: Int) {
        do {
            let processes = try ProcessEnumerator.allProcesses()
            let rows = processes.map { analysisRow(for: $0, config: config) }
            let actionable = rows.filter { $0.decision.hasPrefix("BOOST") }.count
            let backgrounded = rows.filter { $0.background == "yes" }.count
            let protected = rows.filter { $0.rank == 2 }.count
            let skipped = rows.filter { $0.rank == 3 }.count

            print("MACPI process analysis")
            print("Policy: \(config.policyEnabled ? "enabled" : "disabled")")
            print("Mode: \(config.policyMode.rawValue)")
            print("System critical protection: \(config.protectSystemCritical ? "on" : "off")")
            print("Protected whitelist: \(config.whitelistedProcessNames.sorted().joined(separator: ", ").ifEmpty("none"))")
            print("Processes: total=\(processes.count) actionable=\(actionable) backgrounded=\(backgrounded) protected=\(protected) skipped=\(skipped)")
            print("")
            print("\(padded("PID", 7)) \(padded("NAME", 24)) \(padded("BG", 5)) \(padded("DECISION", 14)) REASON")

            rows
                .sorted { lhs, rhs in
                    if lhs.rank != rhs.rank {
                        return lhs.rank < rhs.rank
                    }
                    if lhs.background != rhs.background {
                        return lhs.background == "yes"
                    }
                    return lhs.pid < rhs.pid
                }
                .prefix(limit)
                .forEach { row in
                    print("\(padded(String(row.pid), 7)) \(padded(row.name, 24)) \(padded(row.background, 5)) \(padded(row.decision, 14)) \(row.reason)")
                }
        } catch {
            Logger.error("Failed to analyze processes: \(error)")
        }
    }

    private static func analysisRow(for process: SystemProcess, config: MACPIConfig) -> (pid: pid_t, name: String, background: String, decision: String, reason: String, rank: Int) {
        let name = process.processName.isEmpty ? "?" : process.processName
        let background = backgroundText(pid: process.pid)

        guard config.policyEnabled else {
            return (process.pid, name, background, "DISABLED", "master switch is off", 4)
        }
        if !config.onlyPIDs.isEmpty, !config.onlyPIDs.contains(process.pid) {
            return (process.pid, name, background, "SKIP", "outside --only-pid filter", 3)
        }
        if process.pid <= 1 {
            return (process.pid, name, background, "PROTECTED", "pid <= 1", 2)
        }
        if process.pid == getpid() {
            return (process.pid, name, background, "PROTECTED", "MACPI helper process", 2)
        }
        if !config.includeSystemProcesses, !isUserProcessForAnalysis(process) {
            return (process.pid, name, background, "SYSTEM", "non-user process skipped by default", 2)
        }
        if config.whitelistedProcessNames.contains(name) {
            return (process.pid, name, background, "WHITELIST", "protected whitelist", 2)
        }
        if config.excludedProcessNames.contains(name) {
            return (process.pid, name, background, "PROTECTED", "built-in exclusion", 2)
        }
        if config.protectSystemCritical,
           MACPIConfig.systemCriticalProcessNames.contains(name) {
            return (process.pid, name, background, "SYSTEM", "system critical protection", 2)
        }
        if config.policyMode == .balanced, background != "yes" {
            return (process.pid, name, background, "SKIP", "balanced mode only boosts backgrounded processes", 3)
        }
        if config.policyMode == .aggressive || config.aggressiveRenice {
            return (process.pid, name, background, "BOOST+RENICE", "clear background policy and renice", 0)
        }
        return (process.pid, name, background, "BOOST", "clear background policy", 1)
    }

    private static func isUserProcessForAnalysis(_ process: SystemProcess) -> Bool {
        process.uid == getuid() || (process.uid >= 500 && process.uid != uid_t.max)
    }

    private static func backgroundText(pid: pid_t) -> String {
        switch DarwinScheduler.isDarwinBackground(pid: pid) {
        case .success(true):
            return "yes"
        case .success(false):
            return "no"
        case .failure:
            return "?"
        }
    }

    private static func padded(_ text: String, _ width: Int) -> String {
        let clipped = String(text.prefix(width))
        return clipped + String(repeating: " ", count: max(0, width - clipped.count))
    }

    private static func runSelfTest() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["20"]
        try process.run()

        let pid = process.processIdentifier
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        if let failure = DarwinScheduler.restoreBackgroundPolicy(pid: pid) {
            throw MACPIError.commandFailed("self-test failed: could not put temporary process into Darwin background: \(failure)")
        }
        guard case .success(true) = DarwinScheduler.isDarwinBackground(pid: pid) else {
            throw MACPIError.commandFailed("self-test failed: temporary process did not report Darwin background before boost")
        }

        var config = MACPIConfig()
        config.managePowerSettings = false
        config.onlyPIDs = [pid]

        let engine = PolicyEngine(config: config)
        engine.applyACPolicy(includePowerSettings: false, forceReapply: true)
        guard case .success(false) = DarwinScheduler.isDarwinBackground(pid: pid) else {
            throw MACPIError.commandFailed("self-test failed: AC policy did not clear Darwin background")
        }

        engine.applyBatteryPolicy()
        guard case .success(true) = DarwinScheduler.isDarwinBackground(pid: pid) else {
            throw MACPIError.commandFailed("self-test failed: battery policy did not restore Darwin background")
        }

        print("self-test ok: AC boost cleared Darwin background and battery policy restored it for pid \(pid)")
    }

    private static func printStatus() {
        let power = PowerSource.current()
        let cpu = CPUInfo.current()
        let uidText = geteuid() == 0 ? "root" : "user"

        print("MACPI status")
        print("Power source: \(power.rawValue)")
        print("Effective user: \(uidText)")

        if let pCores = cpu.performanceCoreCount {
            let name = cpu.performanceLevelName ?? "performance"
            print("\(name) cores: \(pCores)")
        } else {
            print("Performance cores: unavailable")
        }

        if let eCores = cpu.efficiencyCoreCount {
            let name = cpu.efficiencyLevelName ?? "efficiency"
            print("\(name) cores: \(eCores)")
        } else {
            print("Efficiency cores: unavailable")
        }
    }

    private static func printUsage() {
        print("""
        MACPI - AC-aware performance policy helper for Apple Silicon Macs

        Usage:
          macpi daemon [options]
          macpi once [options]
          macpi analyze [options]
          macpi status
          macpi self-test
          macpi help

        Options:
          --interval <seconds>           Daemon scan interval, minimum 3 seconds. Default: 15.
          --reapply-interval <seconds>   Minimum seconds before refreshing an already-seen PID. Default: 60.
          --policy-disabled              Keep daemon running but do not change process or power policy.
          --policy-enabled <bool>        true/false master switch. Default: true.
          --policy-mode <mode>           balanced, performance, or aggressive. Default: balanced.
          --dry-run                      Print intended actions without changing system state.
          --aggressive-renice            Also renice touched processes to -5. Requires root and may be disruptive.
          --no-power-settings            Do not call pmset.
          --no-restore-background-on-battery
                                        Do not restore originally backgrounded processes when switching to battery.
          --no-protect-system-critical   Allow touching names in the system-critical protection list.
          --include-system-processes     Allow non-user/root processes to be considered.
          --battery-low-power <mode>     on, off, or unchanged. Default: unchanged.
          --exclude <process-name>       Add a process basename to the exclusion list.
          --whitelist <names>            Comma-separated process names to protect from MACPI policy.
          --only-pid <pid>               Diagnostic/testing mode: touch only the supplied PID. Repeatable.
          --limit <count>                analyze only: number of rows to print. Default: 40.

        Notes:
          macOS does not provide a public API to pin arbitrary processes to P cores.
          MACPI uses public scheduling and power policy controls that bias work toward performance.
        """)
    }
}

public enum MACPIMain {
    public static func main() {
        do {
            try CLI.run(arguments: CommandLine.arguments)
        } catch {
            fputs("macpi: \(error)\n", stderr)
            try? CLI.run(arguments: ["macpi", "help"])
            exit(64)
        }
    }
}
