import SwiftUI

enum WindowTheme {
    static let windowBackground = Color(hex: 0x141414)
    static let panelBackground = Color(hex: 0x1A1A1A)
    static let primaryText = Color(hex: 0xD9D6D0)
    static let secondaryText = Color(hex: 0xA7A49E)
    static let externalIPText = Color(hex: 0x878787)
    static let subduedLog = Color(hex: 0x858585)
    static let errorLog = Color(hex: 0xE36D6D)
    static let warningLog = Color(hex: 0xD7E36D)
    static let busyCircle = Color(hex: 0xD1B228)
    static let connectedCircle = Color(hex: 0x41D17F)
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
