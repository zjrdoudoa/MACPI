import Foundation
import MACPIAppSupport

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

@discardableResult
private func runMACPIAppSupportAssertions() -> Bool {
    expect(LaunchDaemonConstants.label == "com.local.macpi", "LaunchDaemon label should be fixed")
    expect(LaunchDaemonConstants.plistPath == "/Library/LaunchDaemons/com.local.macpi.plist", "plist path should be fixed")
    expect(LaunchDaemonConstants.serviceTarget == "system/com.local.macpi", "service target should be fixed")

    let quoted = ShellQuote.quote("/tmp/with spaces/'and quotes'")
    expect(quoted == "'/tmp/with spaces/'\\''and quotes'\\'''", "single-quote escaping should be shell safe")

    let data = try! LaunchDaemonPlistFactory.makePlistData(arguments: [LaunchDaemonConstants.helperPath, "daemon"])
    let plist = try! PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
    expect(plist["Label"] as? String == "com.local.macpi", "plist should use the fixed label")
    let arguments = plist["ProgramArguments"] as? [String]
    expect(arguments == [LaunchDaemonConstants.helperPath, "daemon"], "plist should preserve program arguments")

    let command = LaunchDaemonInstallPlan(
        helperSourcePath: "/tmp/MACPI helper/macpi",
        stagedPlistPath: "/tmp/MACPI helper/com.local.macpi.plist"
    ).shellCommand

    let orderedMarkers = [
        "launchctl bootout system",
        "launchctl print system/com.local.macpi",
        "install -m 0755",
        "chown root:wheel",
        "chmod 0755",
        "install -m 0644",
        "chmod 0644",
        "plutil -lint",
        "mv -f",
        "launchctl bootstrap system",
        "launchctl kickstart -k system/com.local.macpi"
    ]
    var searchStart = command.startIndex
    for marker in orderedMarkers {
        guard let range = command.range(of: marker, range: searchStart..<command.endIndex) else {
            preconditionFailure("install plan should contain ordered marker: \(marker)")
        }
        searchStart = range.upperBound
    }
    expect(command.contains("'/tmp/MACPI helper/macpi'"), "helper path should be shell quoted")
    expect(command.contains("'/tmp/MACPI helper/com.local.macpi.plist'"), "staged plist path should be shell quoted")

    return true
}

private let macpiAppSupportAssertionsPassed = runMACPIAppSupportAssertions()
