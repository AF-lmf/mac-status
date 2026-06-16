import Foundation
import SQLite3

// MARK: - History Store

/// SQLite-backed persistence layer for metric samples.
/// Uses the sqlite3 C API directly — zero external dependencies.
///
/// Thread safety: All database operations run on a serial DispatchQueue
/// to prevent concurrent access. WAL mode enables concurrent reads.
///
/// Schema:
/// ```sql
/// CREATE TABLE IF NOT EXISTS samples (
///     timestamp REAL NOT NULL,
///     cpu REAL,
///     memory REAL,
///     net_upload REAL,
///     net_download REAL,
///     gpu REAL
/// );
/// CREATE INDEX IF NOT EXISTS idx_samples_ts ON samples(timestamp);
/// ```
final class HistoryStore: @unchecked Sendable {

    // MARK: - Properties

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.macstatus.history", qos: .utility)
    private let dbPath: String

    // Prepared statements (lazy, created on first use)
    private var insertStmt: OpaquePointer?
    private var queryRangeStmt: OpaquePointer?
    private var deleteOlderStmt: OpaquePointer?

    // MARK: - Initialization

    init() {
        // Store database in Application Support
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let appDir = appSupport.appendingPathComponent("MacStatus", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.dbPath = appDir.appendingPathComponent("history.db").path

        queue.sync {
            openDatabase()
            createSchema()
        }
    }

    deinit {
        finalizeStatements()
        sqlite3_close(db)
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbPath, &db, Int32(flags), nil) == SQLITE_OK else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            print("[HistoryStore] Failed to open database: \(errMsg)")
            return
        }

        // Enable WAL mode for better concurrent read performance
        execute("PRAGMA journal_mode = WAL")
        execute("PRAGMA synchronous = NORMAL")
        execute("PRAGMA cache_size = -2000") // 2MB cache
    }

    private func createSchema() {
        execute("""
            CREATE TABLE IF NOT EXISTS samples (
                timestamp REAL NOT NULL,
                cpu REAL,
                memory REAL,
                net_upload REAL,
                net_download REAL,
                gpu REAL
            )
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_samples_ts ON samples(timestamp)")
    }

    private func finalizeStatements() {
        if let stmt = insertStmt { sqlite3_finalize(stmt) }
        if let stmt = queryRangeStmt { sqlite3_finalize(stmt) }
        if let stmt = deleteOlderStmt { sqlite3_finalize(stmt) }
        insertStmt = nil
        queryRangeStmt = nil
        deleteOlderStmt = nil
    }

    // MARK: - Insert

    /// Insert a batch of samples into the database.
    func insertSamples(_ samples: [MetricSample]) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }

            // Prepare insert statement
            if self.insertStmt == nil {
                let sql = "INSERT INTO samples (timestamp, cpu, memory, net_upload, net_download, gpu) VALUES (?, ?, ?, ?, ?, ?)"
                guard sqlite3_prepare_v2(db, sql, -1, &self.insertStmt, nil) == SQLITE_OK else {
                    return
                }
            }

            sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)

            for sample in samples {
                guard let stmt = self.insertStmt else { continue }
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                sqlite3_bind_double(stmt, 1, sample.timestamp.timeIntervalSince1970)
                self.bindOptionalDouble(stmt, index: 2, value: sample.cpuUsage)
                self.bindOptionalDouble(stmt, index: 3, value: sample.memoryUsage)
                self.bindOptionalDouble(stmt, index: 4, value: sample.networkUploadBps)
                self.bindOptionalDouble(stmt, index: 5, value: sample.networkDownloadBps)
                self.bindOptionalDouble(stmt, index: 6, value: sample.gpuUsage)

                sqlite3_step(stmt)
            }

            sqlite3_exec(db, "COMMIT", nil, nil, nil)
        }
    }

    /// Insert a single sample (convenience).
    func insert(_ sample: MetricSample) {
        insertSamples([sample])
    }

    // MARK: - Query

    /// Query samples within a time range.
    func querySamples(from start: Date, to end: Date) -> [MetricSample] {
        var results: [MetricSample] = []

        queue.sync { [self] in
            guard let db = self.db else { return }

            if self.queryRangeStmt == nil {
                let sql = "SELECT timestamp, cpu, memory, net_upload, net_download, gpu FROM samples WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp ASC"
                guard sqlite3_prepare_v2(db, sql, -1, &self.queryRangeStmt, nil) == SQLITE_OK else {
                    return
                }
            }

            guard let stmt = self.queryRangeStmt else { return }
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)

            sqlite3_bind_double(stmt, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, end.timeIntervalSince1970)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let ts = sqlite3_column_double(stmt, 0)
                let cpu = columnOptionalDouble(stmt, index: 1)
                let mem = columnOptionalDouble(stmt, index: 2)
                let netUp = columnOptionalDouble(stmt, index: 3)
                let netDown = columnOptionalDouble(stmt, index: 4)
                let gpu = columnOptionalDouble(stmt, index: 5)

                results.append(MetricSample(
                    timestamp: Date(timeIntervalSince1970: ts),
                    cpuUsage: cpu,
                    memoryUsage: mem,
                    networkUploadBps: netUp,
                    networkDownloadBps: netDown,
                    gpuUsage: gpu
                ))
            }
        }

        return results
    }

    // MARK: - Cleanup

    /// Delete samples older than the given date.
    func purgeOlder(than date: Date) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }

            if self.deleteOlderStmt == nil {
                let sql = "DELETE FROM samples WHERE timestamp < ?"
                guard sqlite3_prepare_v2(db, sql, -1, &self.deleteOlderStmt, nil) == SQLITE_OK else {
                    return
                }
            }

            guard let stmt = self.deleteOlderStmt else { return }
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
            sqlite3_step(stmt)
        }
    }

    /// Get the total number of stored samples.
    var sampleCount: Int {
        var count = 0
        queue.sync { [self] in
            guard let db = self.db else { return }
            let sql = "SELECT COUNT(*) FROM samples"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int64(stmt, 0))
            }
        }
        return count
    }

    // MARK: - Helpers

    private func execute(_ sql: String) {
        guard let db = self.db else { return }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg {
                print("[HistoryStore] SQL error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer, index: Int32, value: Double?) {
        if let value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnOptionalDouble(_ stmt: OpaquePointer, index: Int32) -> Double? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return sqlite3_column_double(stmt, index)
    }
}
