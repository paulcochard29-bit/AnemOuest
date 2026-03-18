//
//  UIComponents.swift
//  AnemOuest
//
//  Reusable UI components extracted from ContentView
//

import SwiftUI

// MARK: - Glass Modifiers

struct LiquidGlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
    }
}

struct LiquidGlassRoundedModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var useGlassEffect: Bool = false

    func body(content: Content) -> some View {
        if useGlassEffect, #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
    }
}

struct LiquidGlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
    }
}

// MARK: - Shimmer Loading Effect

struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(UIColor.systemGray5),
                    Color(UIColor.systemGray4),
                    Color(UIColor.systemGray5)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 2)
            .offset(x: phase * geo.size.width - geo.size.width)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: phase * geo.size.width * 1.5 - geo.size.width * 0.25)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Sensor Marker (small arrow + colored numbers)

struct SensorMarker: View {
    let name: String
    let latest: WCWindObservation?
    let isSelected: Bool

    private var wind: Double? { latest?.ws.moy.value }
    private var gust: Double? { latest?.ws.max.value }
    private var dir: Double?  { latest?.wd.moy.value }

    var body: some View {
        VStack(spacing: 4) {
            CleanArrow(deg: dir ?? 0, isSelected: isSelected)
            CapsulePill(wind: wind, gust: gust, isSelected: isSelected)
        }
    }
}

struct CapsulePill: View {
    let wind: Double?
    let gust: Double?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(fmt(wind))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(color(wind))

            Text("/")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(fmt(gust))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(color(gust))

            Text(WindUnit.current.symbol)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(isSelected ? 0.16 : 0.10), lineWidth: isSelected ? 1.2 : 0.9)
        )
        .shadow(radius: isSelected ? 5 : 2)
    }

    private func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(WindUnit.convertValue(v))"
    }

    private func color(_ v: Double?) -> Color {
        guard let v else { return .secondary }
        return windScale(v)
    }
}

// MARK: - Arrow (not colored)

struct CleanArrow: View {
    let deg: Double
    let isSelected: Bool

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: isSelected ? 16 : 14, weight: .semibold))
            .foregroundStyle(.primary.opacity(isSelected ? 1.0 : 0.9))
            .rotationEffect(.degrees(deg + 180))
            .padding(5)
            .background(
                Circle().fill(.thinMaterial).opacity(isSelected ? 0.55 : 0.35)
            )
            .overlay(
                Circle().strokeBorder(Color.white.opacity(isSelected ? 0.14 : 0.08), lineWidth: 0.8)
            )
            .shadow(radius: isSelected ? 3 : 1)
    }
}

// MARK: - Status Pill (Online / Offline)

struct StatusPill: View {
    let isOnline: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOnline ? Color.green : Color.red)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 0.35 : 0.9)
                .scaleEffect(pulse ? 0.92 : 1.0)

            Text(isOnline ? "En ligne" : "Hors ligne")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
        }
    }
}

// MARK: - Station Count Pill (with blinking LED)

struct StationCountPill: View {
    let count: Int
    @State private var pulse = false
    @State private var displayedCount: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            // Blinking green LED
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 0.4 : 1.0)
                .scaleEffect(pulse ? 0.85 : 1.0)
                .shadow(color: .green.opacity(0.6), radius: pulse ? 2 : 4)

            Text("\(displayedCount)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText(value: Double(displayedCount)))

            Text("stations")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .modifier(LiquidGlassCapsuleModifier())
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
            displayedCount = count
        }
        .onChange(of: count) { _, newValue in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                displayedCount = newValue
            }
        }
    }
}

// MARK: - Accuracy Badge

struct AccuracyBadge: View {
    let meanError: Double

    private var color: Color {
        switch meanError {
        case ..<3: return .green      // Excellent: <3 nds
        case ..<4: return .cyan       // Très bon: 3-4 nds
        case ..<5: return .orange     // Bon: 4-5 nds
        default: return .red          // Variable: >5 nds
        }
    }

    private var errorText: String {
        "±\(Int(round(meanError)))"
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("AROME")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(errorText)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(WindUnit.current.symbol)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
            if meanError < 3 {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
        .fixedSize()
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    var icon: String? = nil
    var accentColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accentColor.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Metadata Chip

struct MetadataChip: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
// MARK: - Splash Screen

struct SplashScreenView: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.4, blue: 0.7),
                    Color(red: 0.05, green: 0.25, blue: 0.5)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                // App icon / wind symbol
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 120, height: 120)

                    Image(systemName: "wind")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(isAnimating ? 10 : -10))
                }

                // App name
                Text("Le Vent")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                // Loading indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                    .padding(.top, 10)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Wind color scale (approx from your legend)

func windScale(_ kts: Double) -> Color {
    // Legend (noeuds): <7, 7–10, 11–16, 17–21, 22–27, 28–33, 34–40, 41–47, >48
    switch kts {
    case ..<7:
        // light cyan
        return Color(red: 0.70, green: 0.93, blue: 1.00)
    case ..<11:
        // turquoise
        return Color(red: 0.33, green: 0.85, blue: 0.92)
    case ..<17:
        // green
        return Color(red: 0.35, green: 0.89, blue: 0.52)
    case ..<22:
        // yellow
        return Color(red: 0.97, green: 0.90, blue: 0.33)
    case ..<28:
        // orange
        return Color(red: 0.98, green: 0.67, blue: 0.23)
    case ..<34:
        // red
        return Color(red: 0.95, green: 0.22, blue: 0.26)
    case ..<41:
        // magenta
        return Color(red: 0.83, green: 0.20, blue: 0.67)
    case ..<48:
        // purple
        return Color(red: 0.55, green: 0.24, blue: 0.78)
    default:
        // deep purple
        return Color(red: 0.39, green: 0.24, blue: 0.63)
    }
}
