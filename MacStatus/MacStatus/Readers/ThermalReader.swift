import Darwin
import Foundation
import IOKit

enum SystemThermalState: Sendable, Equatable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            self = .unknown
        }
    }
}

struct ThermalSnapshot: Sendable, Equatable {
    let cpuSocTemperatureCelsius: Double?
    let systemState: SystemThermalState
    let gpuTemperatureCelsius: Double?
    let batteryTemperatureCelsius: Double?
    let capturedAt: Date

    static func unavailable(capturedAt: Date = Date()) -> ThermalSnapshot {
        ThermalSnapshot(
            cpuSocTemperatureCelsius: nil,
            systemState: .unknown,
            gpuTemperatureCelsius: nil,
            batteryTemperatureCelsius: nil,
            capturedAt: capturedAt
        )
    }
}

struct ThermalDiagnosticReading: Sendable, Equatable {
    let sensorGroup: String
    let key: String
    let dataType: String?
    let dataSize: UInt32?
    let temperatureCelsius: Double?
}

enum ThermalSensorCatalog {
    static let supportedModel = "Mac15,9"

    static let mac15_9CPUSoCCandidates = [
        "Te05", "Te0L", "Te0P", "Te0S",
        "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
        "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"
    ]

    static let mac15_9GPUCandidates = [
        "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"
    ]

    static let batterySMCCandidates = ["TB1T", "TB2T"]

    static func cpuSocCandidates(for model: String?) -> [String] {
        model == supportedModel ? mac15_9CPUSoCCandidates : []
    }

    static func gpuCandidates(for model: String?) -> [String] {
        model == supportedModel ? mac15_9GPUCandidates : []
    }
}

final class ThermalReader {

    private let smcReader = SMCReader()

    func setup() {
        smcReader.open()
    }

    func readValue() -> ThermalSnapshot {
        let model = Self.hardwareModel()
        let capturedAt = Date()
        let systemState = SystemThermalState(ProcessInfo.processInfo.thermalState)

        return ThermalSnapshot(
            cpuSocTemperatureCelsius: firstTemperature(
                in: ThermalSensorCatalog.cpuSocCandidates(for: model)
            ),
            systemState: systemState,
            gpuTemperatureCelsius: firstTemperature(
                in: ThermalSensorCatalog.gpuCandidates(for: model)
            ),
            batteryTemperatureCelsius: batteryTemperatureCelsius(),
            capturedAt: capturedAt
        )
    }

    func diagnosticReadings() -> [ThermalDiagnosticReading] {
        let model = Self.hardwareModel()
        let candidates = [
            ("cpuSoc", ThermalSensorCatalog.cpuSocCandidates(for: model)),
            ("gpu", ThermalSensorCatalog.gpuCandidates(for: model)),
            ("battery", ThermalSensorCatalog.batterySMCCandidates)
        ]

        return candidates.flatMap { group, keys in
            keys.map { key in
                let value = smcReader.readRawValue(key: key)
                return ThermalDiagnosticReading(
                    sensorGroup: group,
                    key: key,
                    dataType: value?.dataType,
                    dataSize: value?.dataSize,
                    temperatureCelsius: smcReader.readTemperatureCelsius(key: key)
                )
            }
        }
    }

    private func firstTemperature(in keys: [String]) -> Double? {
        for key in keys {
            if let celsius = smcReader.readTemperatureCelsius(key: key) {
                return celsius
            }
        }
        return nil
    }

    private func batteryTemperatureCelsius() -> Double? {
        appleSmartBatteryTemperatureCelsius() ?? firstTemperature(
            in: ThermalSensorCatalog.batterySMCCandidates
        )
    }

    private func appleSmartBatteryTemperatureCelsius() -> Double? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any],
              let raw = Self.doubleValue(props["Temperature"])
        else { return nil }

        let celsius = raw / 100.0
        return (0...100).contains(celsius) ? celsius : nil
    }

    private static func hardwareModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        default:
            return nil
        }
    }
}
