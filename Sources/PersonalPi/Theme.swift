import Foundation
import SwiftUI

enum Theme {
    static let ink = Color(red: 26 / 255, green: 30 / 255, blue: 35 / 255)
    static let text = Color(red: 35 / 255, green: 39 / 255, blue: 44 / 255)
    static let body = Color(red: 58 / 255, green: 65 / 255, blue: 73 / 255)
    static let secondary = Color(red: 65 / 255, green: 71 / 255, blue: 78 / 255)
    static let muted = Color(red: 107 / 255, green: 114 / 255, blue: 122 / 255)
    static let faint = Color(red: 141 / 255, green: 148 / 255, blue: 156 / 255)
    static let dim = Color(red: 154 / 255, green: 161 / 255, blue: 169 / 255)
    static let pale = Color(red: 173 / 255, green: 179 / 255, blue: 186 / 255)
    static let hairline = Color(red: 229 / 255, green: 232 / 255, blue: 236 / 255)
    static let line = Color(red: 226 / 255, green: 229 / 255, blue: 233 / 255)
    static let rule = Color(red: 238 / 255, green: 240 / 255, blue: 243 / 255)
    static let chrome = Color(red: 242 / 255, green: 243 / 255, blue: 245 / 255)
    static let sidebar = Color(red: 247 / 255, green: 248 / 255, blue: 249 / 255)
    static let panel = Color(red: 251 / 255, green: 251 / 255, blue: 252 / 255)
    static let selected = Color(red: 233 / 255, green: 237 / 255, blue: 242 / 255)
    static let wash = Color(red: 238 / 255, green: 242 / 255, blue: 247 / 255)
    static let userBubble = Color(red: 241 / 255, green: 243 / 255, blue: 246 / 255)
    static let canvas = Color.white
    static let accent = Color(red: 58 / 255, green: 110 / 255, blue: 165 / 255)
    static let accentInk = Color(red: 47 / 255, green: 92 / 255, blue: 136 / 255)
    static let accentSoft = Color(red: 207 / 255, green: 222 / 255, blue: 238 / 255)
    static let accentFill = Color(red: 234 / 255, green: 241 / 255, blue: 248 / 255)
    static let positive = Color(red: 78 / 255, green: 133 / 255, blue: 87 / 255)
    static let warning = Color(red: 163 / 255, green: 120 / 255, blue: 31 / 255)
    static let warningFill = Color(red: 251 / 255, green: 245 / 255, blue: 230 / 255)
    static let warningLine = Color(red: 236 / 255, green: 220 / 255, blue: 180 / 255)
    static let danger = Color(red: 177 / 255, green: 80 / 255, blue: 63 / 255)
    static let dangerFill = Color(red: 192 / 255, green: 85 / 255, blue: 69 / 255)
    static let stopLine = Color(red: 230 / 255, green: 179 / 255, blue: 172 / 255)
    static let idle = Color(red: 194 / 255, green: 199 / 255, blue: 205 / 255)
    static let orange = warning

    static let accentGradient = LinearGradient(colors: [accent, accentInk], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let heroGradient = LinearGradient(colors: [accentFill, canvas], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

enum PiFormat {
    static func path(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func todayLabel(_ date: Date = Date(), locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter.string(from: date)
    }

    static func greeting(name: String? = nil, at date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part: String
        if hour < 12 {
            part = "Good morning"
        } else if hour < 18 {
            part = "Good afternoon"
        } else {
            part = "Good evening"
        }
        if let name, !name.isEmpty {
            return "\(part), \(name)"
        }
        return part
    }

    static func sessionClock(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
           date >= startOfWeek {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    static func dayHeader(_ date: Date, now: Date = Date()) -> String? {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return nil }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 45 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if Calendar.current.isDateInToday(date) {
            return "\(Int(seconds / 3600))h ago"
        }
        return sessionClock(date, now: now)
    }

    static func tokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1000 { return String(format: "%.1fk", Double(value) / 1000) }
        return "\(value)"
    }

    static func cost(_ value: Double) -> String {
        if value >= 1 { return String(format: "$%.2f", value) }
        if value >= 0.01 { return String(format: "$%.2f", value) }
        return String(format: "$%.2f", value)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func duration(_ interval: TimeInterval) -> String {
        if interval < 10 { return String(format: "%.1fs", interval) }
        if interval < 60 { return String(format: "%.0fs", interval) }
        return String(format: "%.0fm", interval / 60)
    }
}

struct PulseDot: View {
    var color: Color = Theme.accent
    var size: CGFloat = 5
    var animated: Bool = true
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(animated && dimmed ? 0.25 : 1)
            .onAppear {
                guard animated else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
    }
}

struct Hairline: View {
    var axis: Axis = .horizontal
    var color: Color = Theme.hairline

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
    }
}

struct MonoLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = Theme.dim
    var tracking: CGFloat = 1.4
    var weight: Font.Weight = .regular

    var body: some View {
        Text(LocalizedStringKey(text))
            .textCase(.uppercase)
            .font(Theme.mono(size, weight: weight))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}
