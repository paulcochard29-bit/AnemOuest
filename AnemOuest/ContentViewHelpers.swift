import SwiftUI
import MapKit

// MARK: - Map Layer View

struct MapLayerView: View {
    @Binding var camera: MapCameraPosition

    let selectedStationId: String?

    let windStations: [WindStation]
    let kiteSpots: [KiteSpot]
    let surfSpots: [SurfSpot]
    let showKiteSpots: Bool
    let showSurfSpots: Bool
    let paraglidingSpots: [ParaglidingSpot]
    let showParaglidingSpots: Bool
    let webcams: [Webcam]
    let waveBuoys: [WaveBuoy]
    let mapStyle: MapStyleOption
    let showSeaMap: Bool
    let isCenteringCamera: Bool
    let showUserLocation: Bool
    let onTapStationById: (String) -> Void
    let onTapKiteSpot: (KiteSpot) -> Void
    let onTapSurfSpot: (SurfSpot) -> Void
    let onTapParaglidingSpot: (ParaglidingSpot) -> Void
    let onTapWebcam: (Webcam) -> Void
    let onTapWaveBuoy: (WaveBuoy) -> Void
    let showPraticableSpots: Bool
    let spotScores: [String: Int]

    private var onlineStationCount: Int {
        windStations.filter { $0.isOnline }.count
    }

    var body: some View {
        mapView
            .ignoresSafeArea()
            .overlay(alignment: .bottomTrailing) {
                stationCountIndicator
                    .allowsHitTesting(false)
            }
    }

    private var stationCountIndicator: some View {
        StationCountPill(count: onlineStationCount)
            .padding(.trailing, 12)
            .padding(.bottom, 15)
    }

    private var mapView: some View {
        OptimizedMapView(
            camera: $camera,
            selectedStationId: selectedStationId,
            windStations: windStations,
            kiteSpots: kiteSpots,
            surfSpots: surfSpots,
            showKiteSpots: showKiteSpots,
            showSurfSpots: showSurfSpots,
            webcams: webcams,
            waveBuoys: waveBuoys,
            mapType: mapStyle.mkMapType,
            showSeaMap: showSeaMap,
            isCenteringCamera: isCenteringCamera,
            showUserLocation: showUserLocation,
            onTapStationById: onTapStationById,
            onTapKiteSpot: onTapKiteSpot,
            onTapSurfSpot: onTapSurfSpot,
            paraglidingSpots: paraglidingSpots,
            showParaglidingSpots: showParaglidingSpots,
            onTapParaglidingSpot: onTapParaglidingSpot,
            onTapWebcam: onTapWebcam,
            onTapWaveBuoy: onTapWaveBuoy,
            showPraticableSpots: showPraticableSpots,
            spotScores: spotScores
        )
    }
}

// MARK: - Map Style Picker

struct MapStylePicker: View {
    @Binding var selectedStyle: MapStyleOption
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Style de carte")
                    .font(.headline)
                    .padding(.top, 8)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(MapStyleOption.allCases) { style in
                        MapStyleCard(
                            style: style,
                            isSelected: selectedStyle == style,
                            onTap: {
                                selectedStyle = style
                                dismiss()
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding(.top, 8)
        }
    }
}

struct MapStyleCard: View {
    let style: MapStyleOption
    let isSelected: Bool
    let onTap: () -> Void

    private var previewColor: Color {
        switch style {
        case .standard: return Color(red: 0.95, green: 0.95, blue: 0.92)
        case .satellite: return Color(red: 0.2, green: 0.3, blue: 0.2)
        case .hybrid: return Color(red: 0.25, green: 0.35, blue: 0.25)
        case .muted: return Color(red: 0.15, green: 0.15, blue: 0.18)
        }
    }

    private var textColor: Color {
        switch style {
        case .standard: return .black
        case .satellite, .hybrid, .muted: return .white
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(previewColor)
                        .frame(height: 70)

                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            Circle().fill(textColor.opacity(0.3)).frame(width: 6, height: 6)
                            RoundedRectangle(cornerRadius: 2).fill(textColor.opacity(0.2)).frame(width: 30, height: 3)
                        }
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 2).fill(textColor.opacity(0.15)).frame(width: 20, height: 2)
                            Circle().fill(textColor.opacity(0.3)).frame(width: 8, height: 8)
                            RoundedRectangle(cornerRadius: 2).fill(textColor.opacity(0.15)).frame(width: 25, height: 2)
                        }
                        HStack(spacing: 6) {
                            Circle().fill(textColor.opacity(0.25)).frame(width: 5, height: 5)
                            RoundedRectangle(cornerRadius: 2).fill(textColor.opacity(0.2)).frame(width: 35, height: 3)
                        }
                    }

                    Image(systemName: style.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(textColor.opacity(0.6))
                        .offset(x: 25, y: -20)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )

                Text(style.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .blue : .primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - HomeView Modifiers

struct HomeViewModifiers: ViewModifier {
    @Binding var showForecastFull: Bool
    @Binding var showAlertConfig: Bool
    @Binding var selectedKiteSpot: KiteSpot?
    let selectedStation: WindStation?
    let haptic: (UIImpactFeedbackGenerator.FeedbackStyle) -> Void

    private var stationName: String {
        if let kite = selectedKiteSpot {
            return kite.name
        }
        return selectedStation?.name ?? "Station"
    }

    private var latitude: Double {
        if let kite = selectedKiteSpot {
            return kite.latitude
        }
        return selectedStation?.latitude ?? 47.5
    }

    private var longitude: Double {
        if let kite = selectedKiteSpot {
            return kite.longitude
        }
        return selectedStation?.longitude ?? -3.0
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showForecastFull) {
                ForecastFullView(
                    stationName: stationName,
                    latitude: latitude,
                    longitude: longitude,
                    onClose: {
                        haptic(.light)
                        showForecastFull = false
                    }
                )
            }
            .sheet(isPresented: $showAlertConfig) {
                if let station = selectedStation {
                    WindAlertConfigView(
                        stationId: station.stableId,
                        stationName: station.name
                    )
                }
            }
    }
}

// MARK: - iPad Panel Padding

struct PanelPaddingModifier: ViewModifier {
    let isRegular: Bool

    func body(content: Content) -> some View {
        if isRegular {
            content
                .padding(.vertical, 12)
                .padding(.trailing, 12)
        } else {
            content
                .padding(.bottom, 10)
                .padding(.horizontal, 12)
        }
    }
}
