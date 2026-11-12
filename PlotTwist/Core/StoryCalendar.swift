import Foundation

enum StoryCalendar {
    static func calendar(_ timezoneID: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: timezoneID) ?? .gmt
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }
    static func dayKey(_ date: Date, timezone: String) -> String {
        let f = DateFormatter()
        f.calendar = calendar(timezone); f.timeZone = f.calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func weekStart(_ date: Date, timezone: String) -> Date {
        let c = calendar(timezone)
        let day = c.startOfDay(for: date)
        let offset = (c.component(.weekday, from: day) + 5) % 7
        return c.date(byAdding: .day, value: -offset, to: day)!
    }
    static func weekID(_ date: Date, timezone: String) -> String { dayKey(weekStart(date, timezone: timezone), timezone: timezone) }
    static func date(_ key: String, timezone: String) -> Date? {
        let f = DateFormatter(); f.calendar = calendar(timezone); f.timeZone = f.calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        return f.date(from: key)
    }
    static func weekEnd(_ date: Date, timezone: String) -> Date {
        calendar(timezone).date(byAdding: .day, value: 7, to: weekStart(date, timezone: timezone))!
    }
    static func canPublish(date: Date, now: Date, timezone: String) -> Bool {
        dayKey(date, timezone: timezone) == dayKey(now, timezone: timezone)
    }
    static func momentID(group: String, user: String, day: String) -> String { "\(group)_\(user)_\(day)" }
}

enum EpisodePlanner {
    /// Round-robin across members before sorting chronologically: no member can monopolize a busy week.
    static func select(_ moments: [Moment], limit: Int = 24) -> [Moment] {
        let sorted = moments.sorted { $0.createdAt < $1.createdAt }
        var buckets = Dictionary(grouping: sorted, by: \.userID)
        let members = buckets.keys.sorted()
        var result: [Moment] = []
        while result.count < limit {
            var added = false
            for member in members where result.count < limit {
                if let first = buckets[member]?.first {
                    result.append(first); buckets[member]?.removeFirst(); added = true
                }
            }
            if !added { break }
        }
        return result.sorted { $0.createdAt < $1.createdAt }
    }
    static func duration(for moment: Moment, trailer: Bool) -> Double {
        trailer ? 1.8 : (moment.mediaType == .photo ? 2.6 : min(4, max(0.1, moment.duration)))
    }
}

enum PlotError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
