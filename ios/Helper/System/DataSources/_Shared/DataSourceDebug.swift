import Foundation

enum DataSourceDebug {
    static func start(_ op: String) {
#if DEBUG
        print("[DataSourceDebug] START \(op)")
#endif
    }

    static func success(_ op: String, count: Int? = nil) {
#if DEBUG
        if let count {
            print("[DataSourceDebug] SUCCESS \(op) count=\(count)")
        } else {
            print("[DataSourceDebug] SUCCESS \(op)")
        }
#endif
    }

    static func failure(_ op: String, _ error: Error) {
#if DEBUG
        print("[DataSourceDebug] FAILURE \(op) error=\(error.localizedDescription)")
#endif
    }
}
