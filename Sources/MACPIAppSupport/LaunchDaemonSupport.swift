import Foundation

public enum LaunchDaemonConstants {
    public static let label = "com.local.macpi"
    public static let helperPath = "/usr/local/sbin/macpi"
    public static let plistPath = "/Library/LaunchDaemons/com.local.macpi.plist"
    public static let serviceTarget = "system/com.local.macpi"
    public static let systemDomain = "system"
}

public enum ShellQuote {
    public static func quote(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public enum LaunchDaemonPlistFactory {
    public static func makePlistData(arguments: [String]) throws -> Data {
        let plist: [String: Any] = [
            "Label": LaunchDaemonConstants.label,
            "ProgramArguments": arguments,
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": "/var/log/macpi.log",
            "StandardErrorPath": "/var/log/macpi.err"
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}

public struct LaunchDaemonInstallPlan {
    public let helperSourcePath: String
    public let stagedPlistPath: String

    public init(helperSourcePath: String, stagedPlistPath: String) {
        self.helperSourcePath = helperSourcePath
        self.stagedPlistPath = stagedPlistPath
    }

    public var shellCommand: String {
        let helper = ShellQuote.quote(helperSourcePath)
        let userStagedPlist = ShellQuote.quote(stagedPlistPath)
        let plist = ShellQuote.quote(LaunchDaemonConstants.plistPath)
        let stagedPlist = ShellQuote.quote("\(LaunchDaemonConstants.plistPath).staged")
        let helperDest = ShellQuote.quote(LaunchDaemonConstants.helperPath)
        let tmpHelper = ShellQuote.quote("\(LaunchDaemonConstants.helperPath).staged")

        return """
        set -eu
        cleanup() {
          /bin/rm -f \(tmpHelper) \(stagedPlist)
        }
        trap cleanup EXIT
        /bin/launchctl bootout system \(plist) >/dev/null 2>&1 || true
        if /bin/launchctl print \(LaunchDaemonConstants.serviceTarget) >/dev/null 2>&1; then
          echo "MACPI service is still running after bootout" >&2
          exit 1
        fi
        /usr/bin/install -d -m 0755 /usr/local/sbin
        /usr/bin/install -m 0755 \(helper) \(tmpHelper)
        /usr/sbin/chown root:wheel \(tmpHelper)
        /bin/chmod 0755 \(tmpHelper)
        /usr/bin/install -m 0644 \(userStagedPlist) \(stagedPlist)
        /usr/sbin/chown root:wheel \(stagedPlist)
        /bin/chmod 0644 \(stagedPlist)
        /usr/bin/plutil -lint \(stagedPlist) >/dev/null
        /bin/mv -f \(tmpHelper) \(helperDest)
        /bin/mv -f \(stagedPlist) \(plist)
        /bin/launchctl bootstrap system \(plist)
        /bin/launchctl kickstart -k \(LaunchDaemonConstants.serviceTarget)
        """
    }
}
