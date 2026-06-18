import Darwin
@testable import MACPICore

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func expectThrows(_ message: String, _ body: () throws -> Void) {
    do {
        try body()
        preconditionFailure(message)
    } catch {
        // Expected.
    }
}

@discardableResult
private func runMACPICoreAssertions() -> Bool {
    let identity = ProcessIdentity(pid: 42, startSec: 100, startUsec: 200)
    expect(identity.description.contains("pid=42"), "ProcessIdentity should describe pid")

    var bsdInfo = proc_bsdinfo()
    bsdInfo.pbi_start_tvsec = 100
    bsdInfo.pbi_start_tvusec = 200
    let exact = ProcessIdentityFactory.identity(
        pid: 42,
        info: bsdInfo,
        returnedLength: Int32(MemoryLayout<proc_bsdinfo>.size)
    )
    expect(exact == identity, "ProcessIdentity must use pid + start time")
    let partial = ProcessIdentityFactory.identity(
        pid: 42,
        info: bsdInfo,
        returnedLength: Int32(MemoryLayout<proc_bsdinfo>.size - 1)
    )
    expect(partial == nil, "partial proc_pidinfo results must be identity unknown")

    let defaultConfig = try! CLI.parseConfig(from: [])
    expect(defaultConfig.policyMode == .balanced, "default policy mode should be balanced")
    expect(defaultConfig.managePowerSettings == false, "default should not manage pmset power settings")
    expect(defaultConfig.whitelistedProcessNames.contains("backupd"), "default protected whitelist should include backupd")

    let unchanged = try! CLI.parseConfig(from: ["--battery-low-power", "unchanged"])
    expect(unchanged.managePowerSettings == false, "battery low power unchanged must be no-op")

    let batteryOn = try! CLI.parseConfig(from: ["--battery-low-power", "on"])
    expect(batteryOn.managePowerSettings == true, "battery low power on should enable battery pmset writes")

    let aggressiveAlias = try! CLI.parseConfig(from: ["--aggressive-renice"])
    expect(aggressiveAlias.policyMode == .aggressive, "--aggressive-renice should normalize to aggressive")
    expect(aggressiveAlias.aggressiveRenice, "--aggressive-renice should keep compatibility flag")

    let readonlyConflict = try! CLI.parseConfig(
        from: ["--policy-disabled", "--policy-mode", "aggressive"],
        validateConflicts: false
    )
    expect(readonlyConflict.policyEnabled == false, "read-only parse may ignore daemon-only conflict")

    expectThrows("--policy-disabled should conflict with policy mode for applying commands") {
        _ = try CLI.parseConfig(from: ["--policy-disabled", "--policy-mode", "aggressive"])
    }
    expectThrows("balanced mode should conflict with aggressive-renice") {
        _ = try CLI.parseConfig(from: ["--policy-mode", "balanced", "--aggressive-renice"])
    }
    expectThrows("--no-power-settings should conflict with battery low power on") {
        _ = try CLI.parseConfig(from: ["--no-power-settings", "--battery-low-power", "on"])
    }
    expectThrows("conflicting repeated policy modes should fail") {
        _ = try CLI.parseConfig(from: ["--policy-mode", "balanced", "--policy-mode", "aggressive"])
    }
    expectThrows("PID must be positive") {
        _ = try CLI.parseConfig(from: ["--only-pid", "0"])
    }
    expectThrows("interval must be at least 3 seconds") {
        _ = try CLI.parseConfig(from: ["--interval", "2"])
    }

    let tracker = ProcessStateTracker()
    expect(tracker.count == 0, "fresh ProcessStateTracker should be empty")
    tracker.prune(liveIdentities: [identity])
    tracker.clear()
    expect(tracker.count == 0, "cleared ProcessStateTracker should be empty")

    return true
}

private let macpiCoreAssertionsPassed = runMACPICoreAssertions()
