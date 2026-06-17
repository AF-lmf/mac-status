import Foundation
import IOKit

// MARK: - SMC Reader

/// Minimal **read-only** client for the Apple System Management Controller (SMC).
///
/// Opens an `AppleSMC` IOKit user-client connection and reads numeric keys such as
/// `PSTR` (whole-system total power, in Watts). Reading SMC keys needs **no special
/// entitlement** (the same technique used by iStat Menus / stats / smcFanControl).
///
/// Every read degrades to `nil` when the connection is unavailable or the key/type
/// is unknown on this hardware, so callers render "—" rather than a fake value —
/// mirroring the project-wide probe-and-nil convention.
///
/// **Concurrency:** main-actor confined in practice. Owned by `BatteryReader`, which
/// is driven synchronously on the `MetricCollector` @MainActor tick. Not `Sendable`;
/// only the resulting `Double` crosses actor boundaries (inside `BatterySnapshot`).
final class SMCReader {

    private var connection: io_connect_t = 0
    private var isOpen = false

    // AppleSMC IOConnectCallStructMethod protocol constants (from Apple's smc.c)
    private static let kernelIndexSMC: UInt32 = 2
    private static let cmdReadBytes: UInt8 = 5
    private static let cmdReadKeyInfo: UInt8 = 9

    /// `'flt '` four-char type → 32-bit IEEE-754 float, little-endian.
    /// Power keys (e.g. `PSTR`) are this type on T2 and Apple Silicon Macs.
    private static let typeFLT: UInt32 = 0x666c7420

    // MARK: - Param Struct (mirrors smc.c `SMCKeyData_t` — 80 bytes)

    private typealias SMCBytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
        // CRITICAL: 3 explicit trailing pad bytes. The C `SMCKeyData_keyInfo_t` is
        // 12 bytes (1-byte `dataAttributes` + 3 bytes tail padding to 4-align).
        // Swift, unlike C, *reuses* a nested struct's tail padding for the parent's
        // next fields — without these pads SMCParamStruct collapses to 76 bytes and
        // every field after keyInfo shifts, so the kernel rejects the call and ALL
        // reads silently fail. Padding to a full 12-byte size restores the 80-byte
        // layout the AppleSMC user-client expects. (Verified: stride must == 80.)
        var pad0: UInt8 = 0
        var pad1: UInt8 = 0
        var pad2: UInt8 = 0
    }

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: SMCBytes32 = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    // MARK: - Lifecycle

    /// Open the AppleSMC user-client connection. Idempotent; call once before reads.
    /// Returns `false` (and leaves all reads degrading to nil) when SMC is unavailable.
    @discardableResult
    func open() -> Bool {
        guard !isOpen else { return true }
        // Guard the C-ABI struct layout: the AppleSMC user-client expects exactly
        // 80 bytes. If a future toolchain changes layout, refuse rather than send a
        // malformed request (which would read garbage power values).
        assert(MemoryLayout<SMCParamStruct>.stride == 80, "SMCParamStruct must be 80 bytes")
        guard MemoryLayout<SMCParamStruct>.stride == 80 else { return false }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        isOpen = (result == kIOReturnSuccess)
        return isOpen
    }

    /// Close the connection. Runs automatically on deinit.
    func close() {
        if isOpen {
            IOServiceClose(connection)
            connection = 0
            isOpen = false
        }
    }

    deinit { close() }

    // MARK: - Read

    /// Read a 4-char SMC key as a `Double`. Returns `nil` if the connection is closed,
    /// the key is absent, or the value type is not a recognized numeric format.
    func readValue(key: String) -> Double? {
        guard isOpen else { return nil }

        // Step 1 — key info (data size + type)
        var info = SMCParamStruct()
        info.key = Self.fourCharCode(key)
        info.data8 = Self.cmdReadKeyInfo
        guard let infoOut = call(info), infoOut.result == 0 else { return nil }

        let size = infoOut.keyInfo.dataSize
        let type = infoOut.keyInfo.dataType
        guard size > 0 else { return nil }

        // Step 2 — read raw bytes
        var read = SMCParamStruct()
        read.key = Self.fourCharCode(key)
        read.keyInfo.dataSize = size
        read.data8 = Self.cmdReadBytes
        guard let readOut = call(read), readOut.result == 0 else { return nil }

        return Self.decode(type: type, size: size, bytes: readOut.bytes)
    }

    // MARK: - Private

    private func call(_ input: SMCParamStruct) -> SMCParamStruct? {
        var inputCopy = input
        var output = SMCParamStruct()
        let structSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = structSize
        let result = IOConnectCallStructMethod(
            connection,
            Self.kernelIndexSMC,
            &inputCopy,
            structSize,
            &output,
            &outputSize
        )
        return result == kIOReturnSuccess ? output : nil
    }

    /// Pack up to the first 4 ASCII chars of `s` into a big-endian FourCharCode.
    private static func fourCharCode(_ s: String) -> UInt32 {
        var code: UInt32 = 0
        for byte in s.utf8.prefix(4) {
            code = (code << 8) | UInt32(byte)
        }
        return code
    }

    /// Decode `size` raw bytes per the SMC value `type`.
    /// Handles `'flt '` (LE float) and `'spXY'`/`'fpXY'` (BE signed/unsigned fixed-point).
    private static func decode(type: UInt32, size: UInt32, bytes: SMCBytes32) -> Double? {
        let raw = withUnsafeBytes(of: bytes) { Array($0.prefix(Int(size))) }

        // 'flt ' — 32-bit float, little-endian (power keys on T2 / Apple Silicon)
        if type == typeFLT, raw.count >= 4 {
            let bits = UInt32(raw[0]) | (UInt32(raw[1]) << 8)
                     | (UInt32(raw[2]) << 16) | (UInt32(raw[3]) << 24)
            return Double(Float(bitPattern: bits))
        }

        // 'spXY' / 'fpXY' — signed/unsigned fixed-point, big-endian 16-bit
        let typeChars = withUnsafeBytes(of: type.bigEndian) { Array($0) }
        if raw.count >= 2,
           typeChars[1] == UInt8(ascii: "p"),
           let fracBits = hexDigit(typeChars[3]) {
            let rawValue = UInt16(raw[0]) << 8 | UInt16(raw[1])
            let divisor = Double(1 << fracBits)
            if typeChars[0] == UInt8(ascii: "s") {
                return Double(Int16(bitPattern: rawValue)) / divisor
            } else if typeChars[0] == UInt8(ascii: "f") {
                return Double(rawValue) / divisor
            }
        }

        return nil
    }

    private static func hexDigit(_ c: UInt8) -> Int? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(c - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return Int(c - UInt8(ascii: "a")) + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return Int(c - UInt8(ascii: "A")) + 10
        default: return nil
        }
    }
}
