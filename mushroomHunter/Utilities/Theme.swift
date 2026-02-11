import SwiftUI

enum Theme {
    static func backgroundGradient(for scheme: ColorScheme) -> LinearGradient {
        let colors: [Color]
        switch scheme {
        case .dark:
            colors = [
                Color(red: 0.20, green: 0.14, blue: 0.06),
                Color(red: 0.28, green: 0.18, blue: 0.07),
                Color(red: 0.18, green: 0.12, blue: 0.06)
            ]
        default:
            colors = [
                Color(red: 0.99, green: 0.94, blue: 0.78),
                Color(red: 0.98, green: 0.86, blue: 0.60),
                Color(red: 0.96, green: 0.80, blue: 0.52)
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
            return Color(red: 0.22, green: 0.16, blue: 0.09).opacity(0.95)
        default:
            return Color(red: 1.00, green: 0.97, blue: 0.90).opacity(0.95)
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
