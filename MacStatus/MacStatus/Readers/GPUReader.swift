import Darwin
import Foundation
import IOKit

// MARK: - GPU Pressure Model

enum GPUPressureLevel: Sendable, Equatable {
    case normal
    case warning
    case critical
}

// MARK: - Sendable GPU Stats Wrapper

struct GPUStats: Sendable, Equatable {
    let utilizationPercent: Double
    let pressureLevel: GPUPressureLevel?
}

// MARK: - GPU Reader

/// Reads GPU utilization from IOKit `IOAccelerator` services.
///
/// Different GPU families expose different `PerformanceStatistics` keys, so
/// this reader probes several known utilization keys and uses the highest
/// valid value as the aggregate v1 display value.
final class GPUReader: TimerReader<GPUStats> {

    private static let utilizationKeys = [
        "Device Utilization %",
        "GPU Activity(%)",
        "Renderer Utilization %",
        "Tiler Utilization %",
    ]

    private let isAppleSilicon: Bool

    init() {
        isAppleSilicon = Self.detectAppleSilicon()
        super.init(interval: 2.0)
    }

    override func read() {
        guard let matching = IOServiceMatching("IOAccelerator") else {
            onUpdate?(nil)
            return
        }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else {
            onUpdate?(nil)
            return
        }
        defer { IOObjectRelease(iterator) }

        var bestUtilization: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let statistics = performanceStatistics(for: service),
                  let utilization = utilizationPercent(from: statistics) else {
                continue
            }

            bestUtilization = max(bestUtilization ?? utilization, utilization)
        }

        guard let utilization = bestUtilization else {
            onUpdate?(nil)
            return
        }

        let pressure = isAppleSilicon ? pressureLevel(for: utilization) : nil
        onUpdate?(
            GPUStats(
                utilizationPercent: utilization,
                pressureLevel: pressure
            )
        )
    }

    private func performanceStatistics(for service: io_registry_entry_t) -> [String: Any]? {
        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "PerformanceStatistics" as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }

        return property.takeRetainedValue() as? [String: Any]
    }

    private func utilizationPercent(from statistics: [String: Any]) -> Double? {
        for key in Self.utilizationKeys {
            guard let number = statistics[key] as? NSNumber else { continue }
            return min(max(number.doubleValue, 0), 100)
        }
        return nil
    }

    private func pressureLevel(for utilization: Double) -> GPUPressureLevel {
        switch utilization {
        case ..<60:
            return .normal
        case ..<85:
            return .warning
        default:
            return .critical
        }
    }

    private static func detectAppleSilicon() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }

    /// Synchronous read returning GPUStats directly.
    func readValue() -> GPUStats? {
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var bestUtilization: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let statistics = performanceStatistics(for: service),
                  let utilization = utilizationPercent(from: statistics) else {
                continue
            }

            bestUtilization = max(bestUtilization ?? utilization, utilization)
        }

        guard let utilization = bestUtilization else { return nil }

        let pressure = isAppleSilicon ? pressureLevel(for: utilization) : nil
        return GPUStats(utilizationPercent: utilization, pressureLevel: pressure)
    }
}
