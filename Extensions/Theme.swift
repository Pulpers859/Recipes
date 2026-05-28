import SwiftUI

// MARK: - Recipe Vault Color Theme

extension Color {
    /// Muted olive — primary accent, buttons, active states
    static let rvPrimary = Color(red: 0.486, green: 0.549, blue: 0.302)       // #7C8C4D
    
    /// Warm sage-gold — secondary highlights, selected chips, subtle accents
    static let rvSecondary = Color(red: 0.776, green: 0.753, blue: 0.549)     // #C6C08C
    
    /// Warm cream — card backgrounds, elevated surfaces
    static let rvCream = Color(red: 0.953, green: 0.890, blue: 0.816)         // #F3E3D0
    
    /// Warm taupe — muted text, borders, inactive states
    static let rvTaupe = Color(red: 0.824, green: 0.769, blue: 0.706)         // #D2C4B4
    
    // MARK: - Semantic Aliases
    
    /// Primary accent for buttons, links, tab tint
    static let rvAccent = Color.rvPrimary
    
    /// Muted color for borders, dividers, inactive elements
    static let rvMuted = Color.rvTaupe

    /// Warm canvas for full-screen recipe surfaces
    static let rvBackground = Color(red: 0.978, green: 0.961, blue: 0.929)    // #F9F5ED

    /// Slightly deeper surface used behind hero and filter containers
    static let rvSurface = Color(red: 0.964, green: 0.933, blue: 0.883)       // #F6EEDF

    /// Primary body text on warm surfaces
    static let rvInk = Color(red: 0.204, green: 0.180, blue: 0.165)           // #342E2A

    /// Secondary body text on warm surfaces
    static let rvSubtleText = Color(red: 0.448, green: 0.400, blue: 0.357)    // #72665B

    /// Soft paper surface for cards layered above the warm background
    static let rvPaper = Color(red: 0.992, green: 0.984, blue: 0.965)         // #FDFBF6
}

// MARK: - Gradient Helpers

extension LinearGradient {
    /// Hero gradient for landing surfaces and emphasized cards
    static let rvHeroGradient = LinearGradient(
        colors: [
            .rvBackground,
            .rvSurface,
            .rvCream
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Accent gradient for standout buttons and badges
    static let rvAccentGradient = LinearGradient(
        colors: [
            .rvPrimary,
            .rvSecondary
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}
