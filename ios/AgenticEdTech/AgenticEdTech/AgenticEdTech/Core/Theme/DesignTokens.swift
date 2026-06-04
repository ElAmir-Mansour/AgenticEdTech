import SwiftUI

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

extension Color {
    static let brand = Color(hex: "#6366F1")
    static let brandLight = Color(hex: "#818CF8")
    static let brandDark = Color(hex: "#4F46E5")

    static let success = Color(hex: "#10B981")
    static let warning = Color(hex: "#F59E0B")
    static let error = Color(hex: "#EF4444")
    static let info = Color(hex: "#3B82F6")

    static let heatmapGreen = Color(hex: "#4CAF50")
    static let heatmapYellow = Color(hex: "#FFC107")
    static let heatmapOrange = Color(hex: "#FF9800")
    static let heatmapRed = Color(hex: "#F44336")

    static let agentPlanning = Color(hex: "#8B5CF6")
    static let agentContent = Color(hex: "#3B82F6")
    static let agentAssessment = Color(hex: "#10B981")
    static let agentCritique = Color(hex: "#F59E0B")

    static let bloomRemember = Color(hex: "#94A3B8")
    static let bloomUnderstand = Color(hex: "#60A5FA")
    static let bloomApply = Color(hex: "#34D399")
    static let bloomAnalyze = Color(hex: "#FBBF24")
    static let bloomEvaluate = Color(hex: "#F97316")
    static let bloomCreate = Color(hex: "#EF4444")
}

extension Font {
    static let displayLarge = Font.system(size: 34, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 28, weight: .bold, design: .rounded)
    static let titleLarge = Font.system(size: 22, weight: .semibold)
    static let titleMedium = Font.system(size: 17, weight: .semibold)

    static let bodyLarge = Font.system(size: 17)
    static let bodyMedium = Font.system(size: 15)
    static let bodySmall = Font.system(size: 13)

    static let codeLarge = Font.system(size: 15, design: .monospaced)
    static let codeSmall = Font.system(size: 13, design: .monospaced)

    static let agentLabel = Font.system(size: 12, weight: .bold, design: .rounded)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 1, 1, 1)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
