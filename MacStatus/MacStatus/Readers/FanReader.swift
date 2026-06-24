import Darwin
import Foundation

enum FanSupportState: Sendable, Equatable {
    case supported
    case unsupported
    case expectedButUnreadable
}

struct FanCapabilities: Sendable, Equatable {
    let rpmReadable: Bool
    let boundsReadable: Bool
    let targetReadable: Bool
    let safeControlAvailable: Bool
}

struct FanReading: Sendable, Equatable, Identifiable {
    let id: Int
    let index: Int
    let displayName: String
    let currentRPM: Double?
    let minRPM: Double?
    let maxRPM: Double?
    let targetRPM: Double?
    let capabilities: FanCapabilities
}

struct FanSnapshot: Sendable, Equatable {
    let supportState: FanSupportState
    let fans: [FanReading]
    let capturedAt: Date

    static func unavailable(capturedAt: Date = Date()) -> FanSnapshot {
        FanSnapshot(
            supportState: .unsupported,
            fans: [],
            capturedAt: capturedAt
        )
    }
}

struct FanDiagnosticReading: Sendable, Equatable {
    let key: String
    let dataType: String?
    let dataSize: UInt32?
    let numericValue: Double?
    let rawBytes: [UInt8]
}

enum FanSensorCatalog {
    static let supportedModel = "Mac15,9"
    static let expectedFanCount = 2
    static let saneFanRange = 0...8
    static let diagnosticFanRange = 0..<8
    // SMC fan key family: F(index)Ac, F(index)Mn, F(index)Mx, F(index)Tg.
    static let diagnosticSuffixes = ["Ac", "Mn", "Mx", "Tg", "Sf", "ID", "Md", "md"]

    static func expectsFanSurface(for model: String?) -> Bool {
        model == supportedModel
    }
}

final class FanReader {

    private let smcReader = SMCReader()

    func setup() {
        smcReader.open()
    }

    func readValue() -> FanSnapshot {
        let model = Self.hardwareModel()
        let capturedAt = Date()
        let expectsFanSurface = FanSensorCatalog.expectsFanSurface(for: model)
        guard let fanCount = decodedFanCount() else {
            return unreadableOrUnsupportedSnapshot(
                expectsFanSurface: expectsFanSurface,
                capturedAt: capturedAt
            )
        }

        guard fanCount > 0 else {
            return unreadableOrUnsupportedSnapshot(
                expectsFanSurface: expectsFanSurface,
                capturedAt: capturedAt
            )
        }

        let fans = (0..<fanCount).map { reading(for: $0) }
        let hasReadableRPM = fans.contains { $0.capabilities.rpmReadable }
        return FanSnapshot(
            supportState: hasReadableRPM ? .supported : .expectedButUnreadable,
            fans: fans,
            capturedAt: capturedAt
        )
    }

    func diagnosticReadings() -> [FanDiagnosticReading] {
        let fanKeys = FanSensorCatalog.diagnosticFanRange.flatMap { index in
            FanSensorCatalog.diagnosticSuffixes.map { suffix in
                "F\(index)\(suffix)"
            }
        }
        let keys = ["FNum"] + fanKeys + ["FS! ", "Ftst"]

        return keys.map { key in
            let value = smcReader.readRawValue(key: key)
            return FanDiagnosticReading(
                key: key,
                dataType: value?.dataType,
                dataSize: value?.dataSize,
                numericValue: smcReader.readValue(key: key),
                rawBytes: value?.bytes ?? []
            )
        }
    }

    private func decodedFanCount() -> Int? {
        guard let rawCount = smcReader.readValue(key: "FNum") else { return nil }
        let count = Int(rawCount.rounded())
        return FanSensorCatalog.saneFanRange.contains(count) ? count : nil
    }

    private func unreadableOrUnsupportedSnapshot(
        expectsFanSurface: Bool,
        capturedAt: Date
    ) -> FanSnapshot {
        guard expectsFanSurface else {
            return .unavailable(capturedAt: capturedAt)
        }

        let fans = (0..<FanSensorCatalog.expectedFanCount).map { unreadableReading(for: $0) }
        return FanSnapshot(
            supportState: .expectedButUnreadable,
            fans: fans,
            capturedAt: capturedAt
        )
    }

    private func reading(for index: Int) -> FanReading {
        let current = plausibleRPM(smcReader.readValue(key: "F\(index)Ac"))
        let min = plausibleRPM(smcReader.readValue(key: "F\(index)Mn"))
        let max = plausibleRPM(smcReader.readValue(key: "F\(index)Mx"))
        let target = plausibleRPM(smcReader.readValue(key: "F\(index)Tg"))
        let boundsReadable = {
            guard let min, let max else { return false }
            return min <= max
        }()

        return FanReading(
            id: index,
            index: index,
            displayName: "风扇 \(index + 1)",
            currentRPM: current,
            minRPM: boundsReadable ? min : nil,
            maxRPM: boundsReadable ? max : nil,
            targetRPM: target,
            capabilities: FanCapabilities(
                rpmReadable: current != nil,
                boundsReadable: boundsReadable,
                targetReadable: target != nil,
                safeControlAvailable: false
            )
        )
    }

    private func unreadableReading(for index: Int) -> FanReading {
        FanReading(
            id: index,
            index: index,
            displayName: "风扇 \(index + 1)",
            currentRPM: nil,
            minRPM: nil,
            maxRPM: nil,
            targetRPM: nil,
            capabilities: FanCapabilities(
                rpmReadable: false,
                boundsReadable: false,
                targetReadable: false,
                safeControlAvailable: false
            )
        )
    }

    private func plausibleRPM(_ value: Double?) -> Double? {
        guard let value, (0...20_000).contains(value) else { return nil }
        return value
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
}
