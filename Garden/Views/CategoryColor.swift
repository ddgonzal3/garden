import SwiftUI

enum CategoryColor {
    private static let palette: [Color] = [
        Color(red: 0.36, green: 0.61, blue: 0.84),  // blue
        Color(red: 0.65, green: 0.55, blue: 0.80),  // purple
        Color(red: 0.83, green: 0.63, blue: 0.34),  // amber
        Color(red: 0.80, green: 0.44, blue: 0.56),  // rose
        Color(red: 0.36, green: 0.74, blue: 0.68),  // teal
        Color(red: 0.79, green: 0.72, blue: 0.36),  // gold
        Color(red: 0.48, green: 0.73, blue: 0.50),  // green
        Color(red: 0.72, green: 0.50, blue: 0.36),  // brown
    ]

    static func color(for category: String) -> Color {
        if category == "Uncategorized" { return Color(.systemGray) }
        let hash = abs(category.hashValue)
        return palette[hash % palette.count]
    }
}
