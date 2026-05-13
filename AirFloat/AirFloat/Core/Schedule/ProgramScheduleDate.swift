import Foundation

struct ProgramScheduleDate: RawRepresentable, Codable, Equatable, Hashable, Comparable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        rawValue = String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func < (lhs: ProgramScheduleDate, rhs: ProgramScheduleDate) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
