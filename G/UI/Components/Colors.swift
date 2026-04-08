import SwiftUI

/// G's color palette — dark, clean, slightly cyberpunk.
extension Color {
    static let gPrimary = Color(red: 0.10, green: 0.10, blue: 0.18)
    static let gPrimaryDark = Color(red: 0.06, green: 0.06, blue: 0.10)
    static let gAccent = Color(red: 0.0, green: 0.83, blue: 1.0)
    static let gAccentDim = Color(red: 0.0, green: 0.83, blue: 1.0).opacity(0.5)
    static let gSurface = Color(red: 0.086, green: 0.13, blue: 0.24)
    static let gSurfaceLight = Color(red: 0.10, green: 0.15, blue: 0.27)
    static let gText = Color(red: 0.92, green: 0.92, blue: 0.92)
    static let gTextDim = Color(red: 0.53, green: 0.57, blue: 0.63)
    static let gUserBubble = Color(red: 0.06, green: 0.20, blue: 0.38)
    static let gAssistantBubble = Color(red: 0.10, green: 0.15, blue: 0.27)
    static let gStatusActive = Color(red: 0.0, green: 0.90, blue: 0.46)
    static let gStatusInactive = Color(red: 1.0, green: 0.32, blue: 0.32)
}
