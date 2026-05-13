import Foundation

enum ProgramWeekday: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    static let defaultRestDays: Set<ProgramWeekday> = [.saturday, .sunday]

    var shortLabel: String {
        switch self {
        case .monday:
            return "MON"
        case .tuesday:
            return "TUE"
        case .wednesday:
            return "WED"
        case .thursday:
            return "THU"
        case .friday:
            return "FRI"
        case .saturday:
            return "SAT"
        case .sunday:
            return "SUN"
        }
    }

    static func from(date: Date, calendar: Calendar = .current) -> ProgramWeekday {
        let weekday = calendar.component(.weekday, from: date)
        switch weekday {
        case 1:
            return .sunday
        case 2:
            return .monday
        case 3:
            return .tuesday
        case 4:
            return .wednesday
        case 5:
            return .thursday
        case 6:
            return .friday
        default:
            return .saturday
        }
    }
}
