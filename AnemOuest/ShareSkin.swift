import SwiftUI

// MARK: - Share Skin

enum ShareSkin: String, CaseIterable, Identifiable {
    // Gradient skins
    case ocean      = "Ocean"
    case sunset     = "Sunset"
    case midnight   = "Midnight"
    case forest     = "Forest"
    case arctic     = "Arctic"
    case volcanic   = "Volcanic"
    case neon       = "Neon"
    case clean      = "Clean"

    // Photo skins
    case photoBeach = "Beach"
    case photoStorm = "Storm"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .ocean:      return "water.waves"
        case .sunset:     return "sunset.fill"
        case .midnight:   return "moon.stars.fill"
        case .forest:     return "leaf.fill"
        case .arctic:     return "snowflake"
        case .volcanic:   return "flame.fill"
        case .neon:       return "bolt.fill"
        case .clean:      return "sun.max.fill"
        case .photoBeach: return "photo"
        case .photoStorm: return "cloud.bolt.fill"
        }
    }

    // MARK: - Light / Dark

    var isPhotoSkin: Bool {
        switch self {
        case .photoBeach, .photoStorm: return true
        default: return false
        }
    }

    var isDark: Bool {
        switch self {
        case .clean, .arctic: return false
        default: return true
        }
    }

    // MARK: - Text Colors

    var primaryTextColor: Color {
        isDark ? .white : .black
    }

    var secondaryTextColor: Color {
        isDark ? .white.opacity(0.6) : .black.opacity(0.5)
    }

    var tertiaryTextColor: Color {
        isDark ? .white.opacity(0.3) : .black.opacity(0.25)
    }

    // MARK: - Accent

    var accentColor: Color {
        switch self {
        case .ocean:      return .cyan
        case .sunset:     return Color(red: 1.0, green: 0.75, blue: 0.3)
        case .midnight:   return Color(red: 0.6, green: 0.5, blue: 1.0)
        case .forest:     return Color(red: 0.5, green: 0.9, blue: 0.5)
        case .arctic:     return Color(red: 0.2, green: 0.6, blue: 0.9)
        case .volcanic:   return Color(red: 1.0, green: 0.45, blue: 0.2)
        case .neon:       return .cyan
        case .clean:      return .cyan
        case .photoBeach: return Color(red: 0.3, green: 0.85, blue: 0.9)
        case .photoStorm: return Color(red: 0.7, green: 0.8, blue: 1.0)
        }
    }

    // MARK: - Gradient Colors

    var gradientColors: [Color] {
        switch self {
        case .ocean:
            return [
                Color(red: 0.05, green: 0.10, blue: 0.20),
                Color(red: 0.08, green: 0.15, blue: 0.30),
                Color(red: 0.05, green: 0.12, blue: 0.25)
            ]
        case .sunset:
            return [
                Color(red: 0.15, green: 0.05, blue: 0.15),
                Color(red: 0.35, green: 0.10, blue: 0.20),
                Color(red: 0.50, green: 0.20, blue: 0.10)
            ]
        case .midnight:
            return [
                Color(red: 0.03, green: 0.02, blue: 0.08),
                Color(red: 0.08, green: 0.05, blue: 0.18),
                Color(red: 0.05, green: 0.03, blue: 0.12)
            ]
        case .forest:
            return [
                Color(red: 0.04, green: 0.12, blue: 0.08),
                Color(red: 0.06, green: 0.18, blue: 0.12),
                Color(red: 0.03, green: 0.10, blue: 0.06)
            ]
        case .arctic:
            return [
                Color(red: 0.88, green: 0.93, blue: 0.97),
                Color(red: 0.82, green: 0.90, blue: 0.96),
                Color(red: 0.90, green: 0.95, blue: 0.98)
            ]
        case .volcanic:
            return [
                Color(red: 0.12, green: 0.04, blue: 0.02),
                Color(red: 0.20, green: 0.06, blue: 0.04),
                Color(red: 0.15, green: 0.05, blue: 0.03)
            ]
        case .neon:
            return [
                Color(red: 0.05, green: 0.02, blue: 0.12),
                Color(red: 0.10, green: 0.03, blue: 0.20),
                Color(red: 0.06, green: 0.02, blue: 0.14)
            ]
        case .clean:
            return [
                Color(red: 0.96, green: 0.96, blue: 0.97),
                Color(red: 0.98, green: 0.98, blue: 0.99),
                Color(red: 0.95, green: 0.95, blue: 0.96)
            ]
        case .photoBeach, .photoStorm:
            return [
                Color(red: 0.05, green: 0.10, blue: 0.20),
                Color(red: 0.08, green: 0.15, blue: 0.30),
                Color(red: 0.05, green: 0.12, blue: 0.25)
            ]
        }
    }

    // MARK: - Decorative Circles

    var decorativeCircleColor1: Color {
        switch self {
        case .ocean:      return .cyan
        case .sunset:     return Color(red: 1.0, green: 0.5, blue: 0.2)
        case .midnight:   return Color(red: 0.4, green: 0.2, blue: 0.8)
        case .forest:     return Color(red: 0.2, green: 0.8, blue: 0.3)
        case .arctic:     return Color(red: 0.4, green: 0.7, blue: 1.0)
        case .volcanic:   return Color(red: 1.0, green: 0.3, blue: 0.1)
        case .neon:       return .cyan
        case .clean:      return Color(red: 0.7, green: 0.85, blue: 1.0)
        case .photoBeach: return .cyan
        case .photoStorm: return Color(red: 0.5, green: 0.6, blue: 0.9)
        }
    }

    var decorativeCircleColor2: Color {
        switch self {
        case .ocean:      return .cyan
        case .sunset:     return Color(red: 0.8, green: 0.3, blue: 0.5)
        case .midnight:   return Color(red: 0.2, green: 0.1, blue: 0.5)
        case .forest:     return Color(red: 0.1, green: 0.6, blue: 0.4)
        case .arctic:     return Color(red: 0.5, green: 0.8, blue: 0.95)
        case .volcanic:   return Color(red: 0.8, green: 0.2, blue: 0.05)
        case .neon:       return Color(red: 1.0, green: 0.2, blue: 0.6)
        case .clean:      return Color(red: 0.8, green: 0.9, blue: 1.0)
        case .photoBeach: return Color(red: 0.2, green: 0.8, blue: 0.6)
        case .photoStorm: return Color(red: 0.3, green: 0.3, blue: 0.6)
        }
    }

    // MARK: - Chart Colors

    var chartWindColor: Color {
        switch self {
        case .clean:   return .blue
        case .arctic:  return Color(red: 0.1, green: 0.5, blue: 0.8)
        case .neon:    return .cyan
        case .sunset:  return Color(red: 1.0, green: 0.85, blue: 0.4)
        default:       return .cyan
        }
    }

    var chartGustColor: Color {
        switch self {
        case .clean:   return .red
        case .arctic:  return .orange
        case .neon:    return Color(red: 1.0, green: 0.2, blue: 0.6)
        case .sunset:  return Color(red: 1.0, green: 0.5, blue: 0.3)
        default:       return .orange
        }
    }

    var chartHm0Color: Color {
        switch self {
        case .clean:   return .cyan
        case .arctic:  return Color(red: 0.1, green: 0.6, blue: 0.8)
        case .neon:    return .cyan
        case .sunset:  return Color(red: 0.3, green: 0.85, blue: 0.9)
        default:       return .cyan
        }
    }

    var chartHmaxColor: Color {
        switch self {
        case .clean:   return .orange
        case .arctic:  return Color(red: 0.9, green: 0.6, blue: 0.2)
        case .neon:    return Color(red: 1.0, green: 0.6, blue: 0.1)
        case .sunset:  return Color(red: 1.0, green: 0.5, blue: 0.3)
        default:       return .orange
        }
    }

    var chartGridColor: Color {
        isDark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    var chartLabelColor: Color {
        isDark ? .white.opacity(0.5) : .black.opacity(0.5)
    }

    // MARK: - Photo

    var photoImageName: String? {
        switch self {
        case .photoBeach: return "skin_beach"
        case .photoStorm: return "skin_storm"
        default: return nil
        }
    }

    var photoOverlayOpacity: Double {
        switch self {
        case .photoBeach: return 0.45
        case .photoStorm: return 0.50
        default: return 0.0
        }
    }

    // MARK: - Thumbnail (for picker)

    var thumbnailColors: [Color] {
        switch self {
        case .ocean:      return [Color(red: 0.1, green: 0.2, blue: 0.4), Color(red: 0.1, green: 0.3, blue: 0.5)]
        case .sunset:     return [Color(red: 0.5, green: 0.15, blue: 0.25), Color(red: 0.6, green: 0.3, blue: 0.15)]
        case .midnight:   return [Color(red: 0.05, green: 0.03, blue: 0.15), Color(red: 0.1, green: 0.05, blue: 0.25)]
        case .forest:     return [Color(red: 0.05, green: 0.2, blue: 0.1), Color(red: 0.08, green: 0.3, blue: 0.15)]
        case .arctic:     return [Color(red: 0.85, green: 0.92, blue: 0.97), Color(red: 0.9, green: 0.95, blue: 1.0)]
        case .volcanic:   return [Color(red: 0.25, green: 0.08, blue: 0.04), Color(red: 0.35, green: 0.12, blue: 0.06)]
        case .neon:       return [Color(red: 0.08, green: 0.03, blue: 0.2), Color(red: 0.15, green: 0.05, blue: 0.3)]
        case .clean:      return [Color(red: 0.95, green: 0.95, blue: 0.96), .white]
        case .photoBeach: return [Color(red: 0.6, green: 0.8, blue: 0.9), Color(red: 0.85, green: 0.75, blue: 0.6)]
        case .photoStorm: return [Color(red: 0.25, green: 0.25, blue: 0.35), Color(red: 0.15, green: 0.15, blue: 0.25)]
        }
    }
}

// MARK: - Background View Builder

extension ShareSkin {

    @ViewBuilder
    func backgroundView(windValue: Double?, windColorFn: (Double) -> Color) -> some View {
        ZStack {
            if let imageName = photoImageName {
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)

                Color.black.opacity(photoOverlayOpacity)
            } else {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            if self != .clean {
                Circle()
                    .fill(
                        isPhotoSkin
                            ? decorativeCircleColor1.opacity(0.1)
                            : (windValue.map { windColorFn($0).opacity(0.2) }
                               ?? decorativeCircleColor1.opacity(0.15))
                    )
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: -80, y: -150)

                Circle()
                    .fill(decorativeCircleColor2.opacity(0.1))
                    .frame(width: 200, height: 200)
                    .blur(radius: 50)
                    .offset(x: 100, y: 200)
            }
        }
    }
}

// MARK: - Share Font Style

enum ShareFontStyle: String, CaseIterable, Identifiable {
    case rounded   = "Arrondi"
    case classic   = "Classique"
    case serif     = "Serif"
    case mono      = "Mono"
    case futura    = "Futura"
    case typewriter = "Machine"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// Create a font for text elements with this style
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .rounded:
            return .system(size: size, weight: weight, design: .rounded)
        case .classic:
            return .system(size: size, weight: weight, design: .default)
        case .serif:
            return .system(size: size, weight: weight, design: .serif)
        case .mono:
            return .system(size: size, weight: weight, design: .monospaced)
        case .futura:
            return .custom(futuraName(for: weight), size: size)
        case .typewriter:
            return .custom(typewriterName(for: weight), size: size)
        }
    }

    private func futuraName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .semibold, .heavy, .black:
            return "Futura-Bold"
        default:
            return "Futura-Medium"
        }
    }

    private func typewriterName(for weight: Font.Weight) -> String {
        switch weight {
        case .black, .heavy, .bold:
            return "AmericanTypewriter-Bold"
        case .semibold:
            return "AmericanTypewriter-Semibold"
        default:
            return "AmericanTypewriter"
        }
    }
}
