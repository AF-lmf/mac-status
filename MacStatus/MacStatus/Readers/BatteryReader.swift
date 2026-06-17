import Foundation
import IOKit
import IOKit.ps
import AppKit

// MARK: - Sendable Battery Snapshot

/// Immutable, value-type-only battery reading that safely crosses actor boundaries.
///
/// All probe-and-nil fields are `Optional` — a `nil` field means the underlying
/// IOKit key was missing or unreadable on this hardware, and the UI degrades that
/// field to "—" rather than showing a fake value. `chargePercent`/`isCharging`/`isOnAC`
/// are non-optional because reaching a non-nil `BatterySnapshot` proves a battery exists.
struct BatterySnapshot: Sendable, Equatable {
    /// Charge level 0–100%. From `kIOPSCurrentCapacityKey`. Always present on laptops.
    let chargePercent: Int

    /// True when actively charging. From `kIOPSIsChargingKey`.
    let isCharging: Bool

    /// True when on external (AC) power. Derived from `kIOPSPowerSourceStateKey == "AC Power"`.
    let isOnAC: Bool

    /// Minutes to empty. `nil` = not applicable / post-wake skip. `-1` = calculating.
    /// Only meaningful when `isOnAC == false`.
    let timeToEmptyMinutes: Int?

    /// Minutes to full. `nil` = not applicable / post-wake skip. `-1` = calculating.
    /// Only meaningful when `isCharging == true`.
    let timeToFullMinutes: Int?

    /// Net power draw in Watts. Positive = charging, negative = discharging.
    /// `nil` if Amperage/Voltage key is missing OR |watts| < 0.1 (idle noise → "—").
    let watts: Double?

    /// Battery health 0–100% = `AppleRawMaxCapacity / DesignCapacity × 100`.
    /// `nil` if either key is missing.
    let healthPercent: Double?

    /// Lifetime charge cycles. `nil` if `CycleCount` key is missing.
    let cycleCount: Int?
}

// MARK: - Battery Reader

/// Reads battery state from two complementary Apple IOKit layers:
///   1. **Power Sources** (`IOPSCopyPowerSourcesInfo`) — charge %, charging state, time estimates.
///   2. **AppleSmartBattery IORegistry** — real-time Watts, health %, cycle count.
///
/// Returns `nil` from `readValue()` on desktop Macs (no `AppleSmartBattery` service),
/// mirroring the v1.0 `GPUReader` nil-degradation pattern. Every IOKit key is read with
/// probe-and-nil (`as?`) — there is no strong-unwrap anywhere, so malformed/absent
/// registry values degrade a field rather than crashing.
///
/// Not a `TimerReader` subclass: `MetricCollector` drives the cadence by calling
/// `readValue()` synchronously on its existing @MainActor tick. A
/// `NSWorkspace.didWakeNotification` observer (mirroring `NetworkReader`) suppresses
/// stale time estimates for a short grace period after wake.
final class BatteryReader {

    // MARK: - Wake Recovery

    /// Token for the `NSWorkspace.didWakeNotification` observer; removed in `deinit`.
    private var wakeObserver: NSObjectProtocol?

    /// Remaining ticks during which time estimates are forced to "计算中" after wake.
    private var postWakeSkipCount: Int = 0

    /// Grace period length: 3 ticks × 2s ≈ 6s for the PMU to recompute post-wake.
    private let postWakeSkipTotal = 3

    // MARK: - Lifecycle

    /// Register the wake observer. Called once before the first read.
    func setup() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main   // 确保写入与 readValue()（@MainActor tick）在同一队列，消除跨线程竞争
        ) { [weak self] _ in
            self?.postWakeSkipCount = self?.postWakeSkipTotal ?? 3
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    // MARK: - Read

    /// Synchronous battery read. Returns `nil` when no internal battery is present
    /// (desktop Mac) so the popover hides the entire battery section.
    func readValue() -> BatterySnapshot? {
        // ── Layer 1: Power Sources (charge%, state, time) ──────────────────────
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        var psDict: [String: Any]?
        for source in list {
            // takeUnretainedValue() — the description is owned by `info`; do NOT release.
            guard let desc = IOPSGetPowerSourceDescription(info, source)?
                                .takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  (desc[kIOPSIsPresentKey] as? Bool) == true
            else { continue }
            psDict = desc
            break
        }

        guard let desc = psDict,
              let chargePercent = desc[kIOPSCurrentCapacityKey] as? Int,
              let isChargingPS = desc[kIOPSIsChargingKey] as? Bool,
              let stateStr = desc[kIOPSPowerSourceStateKey] as? String
        else { return nil }  // No internal battery present → desktop Mac

        let isOnAC = (stateStr == kIOPSACPowerValue)

        // Time-remaining (probe-and-nil). minutes; -1 = calculating; 0 = N/A in current state.
        var timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int
        var timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int

        // Post-wake grace: suppress stale PMU estimates → "计算中" for a few ticks.
        if postWakeSkipCount > 0 {
            postWakeSkipCount -= 1
            timeToEmpty = nil
            timeToFull = nil
        }

        // ── Layer 2: AppleSmartBattery (watts, health, cycles) ─────────────────
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else {
            // No AppleSmartBattery service. We already proved a battery exists via IOPS,
            // so return the Layer-1 fields and degrade the electrical fields to nil.
            return BatterySnapshot(
                chargePercent: chargePercent,
                isCharging: isChargingPS,
                isOnAC: isOnAC,
                timeToEmptyMinutes: timeToEmpty,
                timeToFullMinutes: timeToFull,
                watts: nil,
                healthPercent: nil,
                cycleCount: nil
            )
        }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any]
        else {
            // Battery present in IOPS but registry properties unreadable — degrade gracefully.
            return BatterySnapshot(
                chargePercent: chargePercent,
                isCharging: isChargingPS,
                isOnAC: isOnAC,
                timeToEmptyMinutes: timeToEmpty,
                timeToFullMinutes: timeToFull,
                watts: nil,
                healthPercent: nil,
                cycleCount: nil
            )
        }

        // Watts — probe-and-nil; magnitude from |Amperage×Voltage|, SIGN from IOPS charging
        // state (NOT the Amperage sign, which is not guaranteed across models).
        // |watts| < 0.1 → nil so the UI shows "—" instead of a misleading "+0.0W".
        let watts: Double? = {
            guard let amp = props["Amperage"] as? Int,
                  let volt = props["Voltage"] as? Int else { return nil }
            let magnitude = abs(Double(amp)) / 1000.0 * Double(volt) / 1000.0
            if magnitude < 0.1 { return nil }
            return isChargingPS ? +magnitude : -magnitude
        }()

        // Health % — AppleRawMaxCapacity / DesignCapacity (correct on Apple Silicon AND Intel).
        // NEVER use MaxCapacity: it is 100 (a percentage) on Apple Silicon.
        let healthPercent: Double? = {
            guard let rawMax = props["AppleRawMaxCapacity"] as? Int,
                  let design = props["DesignCapacity"] as? Int,
                  design > 0 else { return nil }
            return min(100.0, Double(rawMax) / Double(design) * 100.0)
        }()

        let cycleCount = props["CycleCount"] as? Int

        return BatterySnapshot(
            chargePercent: chargePercent,
            isCharging: isChargingPS,
            isOnAC: isOnAC,
            timeToEmptyMinutes: timeToEmpty,
            timeToFullMinutes: timeToFull,
            watts: watts,
            healthPercent: healthPercent,
            cycleCount: cycleCount
        )
    }
}
