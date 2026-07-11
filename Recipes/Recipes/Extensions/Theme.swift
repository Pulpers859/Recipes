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

    /// Soft warning surface for recoverable but important guidance
    static let rvWarning = Color(red: 0.700, green: 0.420, blue: 0.110)
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

// MARK: - Design Tokens

enum RVDesign {
    static let screenPadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 20
    static let cardSpacing: CGFloat = 14
    static let cardPadding: CGFloat = 18
    static let cardRadius: CGFloat = 26
    static let controlRadius: CGFloat = 18
    static let heroRadius: CGFloat = 30
}

// MARK: - Shared Surface Modifiers

extension View {
    func rvCard(
        padding: CGFloat = RVDesign.cardPadding,
        radius: CGFloat = RVDesign.cardRadius,
        shadowOpacity: Double = 0.045
    ) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rvPaper)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: 14, y: 7)
    }

    func rvInsetField(radius: CGFloat = RVDesign.controlRadius) -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.rvSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Shared Components

struct RVHeroBanner: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var metrics: [(title: String, value: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                        .foregroundStyle(Color.rvInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.rvSubtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(LinearGradient.rvAccentGradient)
                    .frame(width: 58, height: 58)
                    .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            if !metrics.isEmpty {
                HStack(spacing: 10) {
                    ForEach(metrics.indices, id: \.self) { index in
                        let metric = metrics[index]
                        RVMetricPill(title: metric.title, value: metric.value)
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.rvHeroGradient)
        .clipShape(RoundedRectangle(cornerRadius: RVDesign.heroRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RVDesign.heroRadius, style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
        }
    }
}

struct RVMetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(Color.rvSubtleText)

            Text(value)
                .font(.headline)
                .foregroundStyle(Color.rvInk)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rvPaper.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct RVSectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .serif, weight: .bold))
                .foregroundStyle(Color.rvInk)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.rvSubtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct RVStatusBanner: View {
    enum Tone {
        case info
        case warning
        case success
        case danger

        var color: Color {
            switch self {
            case .info: return .rvPrimary
            case .warning: return .rvWarning
            case .success: return .rvPrimary
            case .danger: return .red
            }
        }

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .success: return "checkmark.circle.fill"
            case .danger: return "xmark.octagon.fill"
            }
        }
    }

    let message: String
    var tone: Tone = .info

    var body: some View {
        Label {
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.rvInk)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: tone.icon)
                .foregroundStyle(tone.color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tone.color.opacity(0.18), lineWidth: 1)
        }
    }
}

struct RVPrimaryButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(LinearGradient.rvAccentGradient, in: RoundedRectangle(cornerRadius: RVDesign.controlRadius, style: .continuous))
            .foregroundStyle(.white)
    }
}

/// Full-screen blocking overlay for short, must-finish work (e.g. writing the
/// safety backup before a delete). Covers the screen so nothing can be edited
/// between snapshotting the data and acting on it.
struct RVBlockingProgressOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color.rvAccent)
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.rvInk)
            }
            .padding(28)
            .background(Color.rvPaper, in: RoundedRectangle(cornerRadius: RVDesign.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 24, y: 8)
        }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
