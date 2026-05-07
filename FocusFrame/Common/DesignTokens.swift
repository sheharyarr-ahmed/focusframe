import SwiftUI

extension Color {
    static let focusBackground = Color(red: 0x0F / 255, green: 0x0F / 255, blue: 0x0F / 255)
    static let focusAccent = Color(red: 0x6E / 255, green: 0xE7 / 255, blue: 0xB7 / 255)
}

extension ShapeStyle where Self == Color {
    static var focusAccent: Color { .focusAccent }
    static var focusBackground: Color { .focusBackground }
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 40
}
