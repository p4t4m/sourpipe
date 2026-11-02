import SwiftUI
import UIKit

extension ThemeColor {
    var color: Color {
        switch self {
        case .green: return Color(red: 0.31, green: 0.62, blue: 0.13)
        case .red: return Color(red: 0.86, green: 0.15, blue: 0.15)
        case .orange: return .orange
        case .yellow: return Color(red: 0.85, green: 0.62, blue: 0.0)
        case .mint: return .mint
        case .teal: return .teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        }
    }
}

extension Appearance {
    var style: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}
