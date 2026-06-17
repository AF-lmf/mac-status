import Darwin
import Foundation

// MARK: - ProcessResourceUsage Sendable Snapshot

/// 单个进程的资源使用快照。Sendable，可安全跨 actor 边界传递（Swift 6 严格并发）。
struct ProcessResourceUsage: Sendable, Equatable {
    /// 进程短名称（proc_name），获取失败时 fallback 为 "PID \(pid)"
    let processName: String
    /// 进程 ID
    let pid: Int32
    /// CPU 占用百分比；nil = 首帧（无前值），UI 显示"—"
    let cpuPercent: Double?
    /// 物理内存独占占用字节数（ri_phys_footprint），对应活动监视器"内存"列
    let memoryBytes: UInt64
}

// MARK: - ProcessResourceReader

/// 基于 libproc 的进程资源采样引擎。
///
/// 持有 (pid, startAbstime) → SnapshotEntry 快照 map，跨采样计算 CPU% delta。
/// 实例由单一 Task.detached(.utility) 循环独占访问，Swift 6 严格并发无需 actor 包装。
///
/// 使用方式：
/// ```swift
/// let result = await Task.detached(priority: .utility) {
///     reader.sample()
/// }.value
/// let (cpuTop5, memTop5) = result
/// ```
final class ProcessResourceReader {

    // MARK: - Nested Types

    /// (pid, 进程启动时间) 复合键，防止 PID 复用导致的 delta 计算错误。
    /// ri_proc_start_abstime 是 Mach absolute time ticks，进程替换时值变化。
    struct ProcessKey: Hashable {
        let pid: Int32
        /// ri_proc_start_abstime（Mach ticks）
        let startAbstime: UInt64
    }

    /// 单帧快照条目，用于下一帧 delta 计算。
    struct SnapshotEntry {
        /// ri_user_time + ri_system_time（Mach ticks，非纳秒）
        let cpuTicks: UInt64
        /// mach_absolute_time() 采样时刻（同单位 Mach ticks）
        let wallTicks: UInt64
    }

    // MARK: - State

    /// 跨采样快照 map。key = (pid, startAbstime)，value = 上一帧 cpu/wall ticks。
    private var prevSnapshot: [ProcessKey: SnapshotEntry] = [:]

    // MARK: - Public Interface

    /// 清空快照 map。popoverDidClose 时调用，保证下次打开首帧重新显示"—"。
    func clearSnapshot() {
        prevSnapshot.removeAll()
    }

    /// 同步采样全部可访问进程，返回 CPU Top 5 与内存 Top 5 两个独立列表。
    ///
    /// - 仅从 Task.detached(priority: .utility) 调用，避免在 MainActor 上执行重 syscall。
    /// - CPU% = max(Δcpu_ticks, 0) / Δwall_ticks × 100（Mach ticks 与壁钟同单位，units 天然抵消，无需额外单位转换）。
    /// - 首帧（无前值）cpuPercent = nil，UI 显示"—"。
    /// - proc_pid_rusage 返回 -1（EPERM/ESRCH/进程已退出）时静默跳过，不崩溃。
    func sample() -> ([ProcessResourceUsage], [ProcessResourceUsage]) {
        // 1. 取壁钟快照（Mach ticks，与 ri_user_time 同单位，units 天然抵消）
        let wallNow = mach_absolute_time()

        // 2. 枚举所有 PID —— 两次调用缓冲区舞蹈（防止两次调用之间进程数增加导致截断）
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return ([], []) }

        let count = Int(needed) / MemoryLayout<Int32>.size
        // 额外分配 10% 防止第二次调用时进程数增多（Pitfall 6）
        var pids = [Int32](repeating: 0, count: count + count / 10)
        let actual = pids.withUnsafeMutableBytes { buf in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buf.baseAddress, Int32(buf.count))
        }
        guard actual > 0 else { return ([], []) }

        // 从第二次返回字节数计算有效 PID 数（不信任第一次 count）
        let pidCount = Int(actual) / MemoryLayout<Int32>.size

        // 3. 遍历 PID，采集 rusage
        var newSnapshot: [ProcessKey: SnapshotEntry] = [:]
        // (进程名, pid, cpuPercent, memBytes)
        var candidates: [(name: String, pid: Int32, cpuPercent: Double?, memBytes: UInt64)] = []

        for i in 0..<pidCount {
            let pid = pids[i]
            // 跳过 pid 0（kernel_task，无法采样，也无意义）
            guard pid > 0 else { continue }

            // 4. proc_pid_rusage —— 推荐写法：UnsafeMutableRawPointer 擦除类型
            //    rusage_info_t 是 void*，proc_pid_rusage 第三参数为 rusage_info_t *（即 void **）
            var info = rusage_info_v4()
            let ret = withUnsafeMutablePointer(to: &info) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, UnsafeMutableRawPointer($0))
            }
            // EPERM（权限不足）或 ESRCH（进程已退出）→ 静默跳过，绝不崩溃（Pitfall 5）
            guard ret == 0 else { continue }

            // 5. 提取字段
            let cpuTicks = info.ri_user_time + info.ri_system_time   // Mach ticks（非纳秒）
            let startAbstime = info.ri_proc_start_abstime              // PID 复用安全键
            let memBytes = info.ri_phys_footprint                      // 应用独占物理内存（非 RSS）

            let key = ProcessKey(pid: pid, startAbstime: startAbstime)

            // 6. 计算 CPU% delta（Pitfall 1：ticks 与 mach_absolute_time 同单位，无需转换）
            var cpuPercent: Double? = nil
            if let prev = prevSnapshot[key] {
                // max(Δcpu, 0) 防计数器异常（Pitfall 2 + T-08-01）
                let deltaCPU: UInt64 = cpuTicks >= prev.cpuTicks ? cpuTicks - prev.cpuTicks : 0
                let deltaWall: UInt64 = wallNow > prev.wallTicks ? wallNow - prev.wallTicks : 0
                if deltaWall > 0 {
                    // min(result, 999.9) 防异常大值（T-08-02）
                    cpuPercent = min(Double(deltaCPU) / Double(deltaWall) * 100.0, 999.9)
                }
            }
            // 首帧：cpuPercent = nil（UI 显示"—"）

            // 7. 更新新快照
            newSnapshot[key] = SnapshotEntry(cpuTicks: cpuTicks, wallTicks: wallNow)

            // 8. 获取进程名（proc_name，256 字节缓冲绰绰有余；MAXCOMLEN=16 太短）
            var nameBuf = [CChar](repeating: 0, count: 256)
            let nameLen = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let name: String = nameLen > 0
                ? String(cString: nameBuf)
                : "PID \(pid)"   // fallback：PID 存在但名称不可读属正常情况

            candidates.append((name: name, pid: pid, cpuPercent: cpuPercent, memBytes: memBytes))
        }

        // 9. 替换快照（本帧成为下帧的 prev）
        prevSnapshot = newSnapshot

        // 10. CPU Top 5 排序：cpuPercent nil 用 -1 sentinel 排末尾；同值按进程名升序 tie-break
        let cpuSorted = candidates.sorted {
            let a = $0.cpuPercent ?? -1
            let b = $1.cpuPercent ?? -1
            if a == b { return $0.name < $1.name }
            return a > b
        }
        let cpuTop5 = Array(cpuSorted.prefix(5)).map {
            ProcessResourceUsage(
                processName: $0.name,
                pid: $0.pid,
                cpuPercent: $0.cpuPercent,
                memoryBytes: $0.memBytes
            )
        }

        // 11. 内存 Top 5 排序：memBytes 降序；同值按进程名升序 tie-break
        let memSorted = candidates.sorted {
            if $0.memBytes == $1.memBytes { return $0.name < $1.name }
            return $0.memBytes > $1.memBytes
        }
        let memTop5 = Array(memSorted.prefix(5)).map {
            ProcessResourceUsage(
                processName: $0.name,
                pid: $0.pid,
                cpuPercent: $0.cpuPercent,
                memoryBytes: $0.memBytes
            )
        }

        return (cpuTop5, memTop5)
    }
}
