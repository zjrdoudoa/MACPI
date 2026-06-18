import Darwin
import Foundation

struct AppCPUCoreTicks {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64

    var active: UInt64 {
        user + system + nice
    }

    var total: UInt64 {
        active + idle
    }
}

final class AppCPUCoreMonitor {
    private var previousTicks: [AppCPUCoreTicks]?

    func sample() -> [Double] {
        guard let current = Self.readTicks(), !current.isEmpty else {
            return []
        }

        defer {
            previousTicks = current
        }

        guard let previousTicks, previousTicks.count == current.count else {
            return Array(repeating: 0, count: current.count)
        }

        return zip(previousTicks, current).map { previous, current in
            let activeDelta = current.active >= previous.active ? current.active - previous.active : 0
            let totalDelta = current.total >= previous.total ? current.total - previous.total : 0
            guard totalDelta > 0 else {
                return 0
            }
            return min(100, max(0, Double(activeDelta) / Double(totalDelta) * 100))
        }
    }

    private static func readTicks() -> [AppCPUCoreTicks]? {
        var coreCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &coreCount,
            &cpuInfo,
            &infoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo else {
            return nil
        }

        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        return (0..<Int(coreCount)).map { index in
            let base = index * Int(CPU_STATE_MAX)
            return AppCPUCoreTicks(
                user: UInt64(cpuInfo[base + Int(CPU_STATE_USER)]),
                system: UInt64(cpuInfo[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt64(cpuInfo[base + Int(CPU_STATE_IDLE)]),
                nice: UInt64(cpuInfo[base + Int(CPU_STATE_NICE)])
            )
        }
    }
}
