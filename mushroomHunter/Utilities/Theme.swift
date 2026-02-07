import SwiftUI

enum Theme {
    static func backgroundGradient(for scheme: ColorScheme) -> LinearGradient {
        let colors: [Color]
        switch scheme {
        case .dark:
            colors = [
                Color(red: 0.08, green: 0.10, blue: 0.09),
                Color(red: 0.12, green: 0.16, blue: 0.12),
                Color(red: 0.10, green: 0.12, blue: 0.15)
            ]
        default:
            colors = [
                Color(red: 0.96, green: 0.94, blue: 0.89),
                Color(red: 0.86, green: 0.92, blue: 0.82),
                Color(red: 0.92, green: 0.87, blue: 0.80)
            ]
        }

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardBackground(for scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color(red: 0.14, green: 0.16, blue: 0.15).opacity(0.95)
        default:
            return Color.white.opacity(0.92)
        }
    }
}

struct ThemedBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Theme.backgroundGradient(for: scheme)
            .ignoresSafeArea()
    }
}
