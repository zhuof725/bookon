import SwiftUI
import Combine

enum ReadTheme: String, CaseIterable, Codable, Identifiable {
    case paper, green, dark
    var id: String { rawValue }
    var name: String {
        switch self { case .paper: return "纸色"; case .green: return "护眼"; case .dark: return "夜间" }
    }
    var background: Color {
        switch self {
        case .paper: return Color(red: 0.96, green: 0.93, blue: 0.86)
        case .green: return Color(red: 0.80, green: 0.90, blue: 0.80)
        case .dark: return Color(red: 0.10, green: 0.10, blue: 0.11)
        }
    }
    var foreground: Color {
        switch self {
        case .dark: return Color(white: 0.75)
        default: return Color(red: 0.15, green: 0.13, blue: 0.10)
        }
    }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

final class ReadSettings: ObservableObject {
    static let shared = ReadSettings()

    @AppStorage("read.fontSize") var fontSize: Double = 19
    @AppStorage("read.lineSpacing") var lineSpacing: Double = 8
    @AppStorage("read.theme") private var themeRaw: String = ReadTheme.paper.rawValue

    var theme: ReadTheme {
        get { ReadTheme(rawValue: themeRaw) ?? .paper }
        set { themeRaw = newValue.rawValue; objectWillChange.send() }
    }

    func bump(_ delta: Double) {
        fontSize = min(max(fontSize + delta, 12), 36)
        objectWillChange.send()
    }
}
