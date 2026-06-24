#if DEBUG
import Foundation

@MainActor
enum DashboardLayoutFixture {
    enum Kind {
        case short
        case extreme
    }

    static func make(_ kind: Kind) -> DashboardState {
        let state = DashboardState()
        apply(kind, to: state)
        return state
    }

    static func apply(_ kind: Kind, to state: DashboardState) {
        switch kind {
        case .short:
            applyShort(to: state)
        case .extreme:
            applyExtreme(to: state)
        }
    }

    static func applyShort(to state: DashboardState) {
        state.cpuUsage = 1
        state.cpuText = "1%"
        state.cpuSamples = [0, 1, 2, 1, 3]

        state.memoryUsage = 2
        state.memoryText = "2% (OK)"
        state.memorySamples = [2, 2, 3, 2, 1]

        state.networkText = "↑1K\n↓2K"
        state.networkProgress = 0.02
        state.networkSamples = [1, 2, 1, 2, 3]

        state.gpuUsage = 0
        state.gpuText = "N/A"
        state.gpuSamples = [0, 0, 1, 0, 0]

        state.battery = BatterySnapshot(
            chargePercent: 88,
            isCharging: false,
            isOnAC: false,
            timeToEmptyMinutes: 95,
            timeToFullMinutes: nil,
            watts: -8.4,
            healthPercent: 96,
            cycleCount: 42,
            systemPowerWatts: 12.5
        )
        state.hasBattery = true

        state.thermal = ThermalSnapshot(
            cpuSocTemperatureCelsius: 35,
            systemState: .nominal,
            gpuTemperatureCelsius: nil,
            batteryTemperatureCelsius: 32,
            capturedAt: Date(timeIntervalSince1970: 1_782_300_000)
        )

        state.fan = FanSnapshot(
            supportState: .supported,
            fans: [
                FanReading(
                    id: 0,
                    index: 0,
                    displayName: "风扇 1",
                    currentRPM: 999,
                    minRPM: 1200,
                    maxRPM: 5200,
                    targetRPM: 1800,
                    capabilities: readableFanCapabilities
                ),
                FanReading(
                    id: 1,
                    index: 1,
                    displayName: "风扇 2",
                    currentRPM: nil,
                    minRPM: nil,
                    maxRPM: nil,
                    targetRPM: nil,
                    capabilities: unreadableFanCapabilities
                )
            ],
            capturedAt: Date(timeIntervalSince1970: 1_782_300_000)
        )

        state.topProcesses = [
            ProcessNetworkUsage(
                processName: "Safari",
                processIdentifier: 101,
                downloadBytesPerSec: 2_000,
                uploadBytesPerSec: 1_000
            ),
            ProcessNetworkUsage(
                processName: "同步",
                processIdentifier: nil,
                downloadBytesPerSec: 0,
                uploadBytesPerSec: 1_200
            )
        ]
        state.processesLoading = false
        state.processError = nil

        state.topCPUProcesses = [
            ProcessResourceUsage(processName: "Xcode", pid: 202, cpuPercent: 0.1, memoryBytes: 512_000),
            ProcessResourceUsage(processName: "助手", pid: 203, cpuPercent: nil, memoryBytes: 128_000)
        ]
        state.topMemoryProcesses = [
            ProcessResourceUsage(processName: "Finder", pid: 301, cpuPercent: 0.2, memoryBytes: 1_024),
            ProcessResourceUsage(processName: "预览", pid: 302, cpuPercent: nil, memoryBytes: 0)
        ]
        state.resourceLoading = false

        state.selfCpuUsage = 0.2
        state.selfMemoryMB = 28
        state.refreshInterval = 2
    }

    static func applyExtreme(to state: DashboardState) {
        state.cpuUsage = 100
        state.cpuText = "100%"
        state.cpuSamples = [0, 25, 50, 75, 100]

        state.memoryUsage = 100
        state.memoryText = "100% (CRIT)"
        state.memorySamples = [60, 70, 80, 90, 100]

        state.networkText = "↑999T\n↓999T"
        state.networkProgress = 1
        state.networkSamples = [0, 250_000, 500_000, 750_000, 999_000]

        state.gpuUsage = 100
        state.gpuText = "100%"
        state.gpuSamples = [10, 40, 70, 90, 100]

        state.battery = BatterySnapshot(
            chargePercent: 100,
            isCharging: true,
            isOnAC: true,
            timeToEmptyMinutes: nil,
            timeToFullMinutes: 5_999,
            watts: 999.9,
            healthPercent: 100,
            cycleCount: 999,
            systemPowerWatts: 999.9
        )
        state.hasBattery = true

        state.thermal = ThermalSnapshot(
            cpuSocTemperatureCelsius: 100,
            systemState: .critical,
            gpuTemperatureCelsius: nil,
            batteryTemperatureCelsius: 100,
            capturedAt: Date(timeIntervalSince1970: 1_782_300_999)
        )

        state.fan = FanSnapshot(
            supportState: .supported,
            fans: [
                FanReading(
                    id: 0,
                    index: 0,
                    displayName: "超长左侧散热模组风扇 1 标签用于截断验证",
                    currentRPM: 9_999,
                    minRPM: 1_234,
                    maxRPM: 9_999,
                    targetRPM: 8_888,
                    capabilities: readableFanCapabilities
                ),
                FanReading(
                    id: 1,
                    index: 1,
                    displayName: "超长右侧散热模组风扇 2 标签用于 N/A 验证",
                    currentRPM: nil,
                    minRPM: nil,
                    maxRPM: nil,
                    targetRPM: nil,
                    capabilities: unreadableFanCapabilities
                )
            ],
            capturedAt: Date(timeIntervalSince1970: 1_782_300_999)
        )

        state.topProcesses = [
            ProcessNetworkUsage(
                processName: "ExtremelyLongUploaderProcessNameForPopoverLayoutYieldValidation",
                processIdentifier: 9_901,
                downloadBytesPerSec: 999_000_000_000_000,
                uploadBytesPerSec: 999_000_000_000_000
            ),
            ProcessNetworkUsage(
                processName: "MixedAvailabilityNetworkRowProcess",
                processIdentifier: nil,
                downloadBytesPerSec: 0,
                uploadBytesPerSec: 0
            )
        ]
        state.processesLoading = false
        state.processError = nil

        state.topCPUProcesses = [
            ProcessResourceUsage(
                processName: "VeryLongCPUProcessNameThatMustYieldBeforeTrailingValue",
                pid: 99_101,
                cpuPercent: 999.9,
                memoryBytes: 999_000_000_000_000
            ),
            ProcessResourceUsage(
                processName: "UnavailableCPUPercentRow",
                pid: 99_102,
                cpuPercent: nil,
                memoryBytes: 1
            )
        ]
        state.topMemoryProcesses = [
            ProcessResourceUsage(
                processName: "VeryLongMemoryProcessNameThatMustYieldBeforeTrailingValue",
                pid: 99_201,
                cpuPercent: 100,
                memoryBytes: 999_000_000_000_000
            ),
            ProcessResourceUsage(
                processName: "MixedAvailabilityMemoryRow",
                pid: 99_202,
                cpuPercent: nil,
                memoryBytes: 0
            )
        ]
        state.resourceLoading = false

        state.selfCpuUsage = 1.1
        state.selfMemoryMB = 999
        state.refreshInterval = 2
    }

    private static let readableFanCapabilities = FanCapabilities(
        rpmReadable: true,
        boundsReadable: true,
        targetReadable: true,
        safeControlAvailable: false
    )

    private static let unreadableFanCapabilities = FanCapabilities(
        rpmReadable: false,
        boundsReadable: false,
        targetReadable: false,
        safeControlAvailable: false
    )

    private enum ExpectedExtremeText {
        static let fanRPM = "9999 RPM"
        static let temperature = "100°C"
        static let unavailable = "N/A"
        static let network = "999T"
        static let chargingPower = "充电 999.9W"
        static let time = "99小时59分"
        static let health = "100%（999 次循环）"
    }
}
#endif
