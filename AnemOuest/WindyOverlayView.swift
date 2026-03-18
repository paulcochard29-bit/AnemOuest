import SwiftUI
import WebKit
import MapKit

// MARK: - Windy Overlay View

/// Full-screen Windy overlay that syncs with the map position
struct WindyOverlayView: View {
    @Binding var isPresented: Bool
    let initialLatitude: Double
    let initialLongitude: Double
    let initialZoom: Int

    @State private var currentLat: Double
    @State private var currentLon: Double
    @State private var currentZoom: Int
    @State private var selectedOverlay: WindyOverlay = .wind
    @State private var selectedModel: WindyModel = .ecmwf
    @State private var webViewId = UUID()

    init(isPresented: Binding<Bool>, latitude: Double, longitude: Double, zoom: Int) {
        self._isPresented = isPresented
        self.initialLatitude = latitude
        self.initialLongitude = longitude
        self.initialZoom = zoom
        self._currentLat = State(initialValue: latitude)
        self._currentLon = State(initialValue: longitude)
        self._currentZoom = State(initialValue: zoom)
    }

    var body: some View {
        ZStack {
            // Windy WebView
            WindyWebView(
                latitude: currentLat,
                longitude: currentLon,
                zoom: currentZoom,
                overlay: selectedOverlay,
                model: selectedModel
            )
            .id(webViewId)
            .ignoresSafeArea()

            // Left sidebar controls
            HStack {
                VStack(spacing: 12) {
                    // Close button
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }

                    // Layer selector (vertical)
                    VStack(spacing: 0) {
                        ForEach(WindyOverlay.allCases) { overlay in
                            Button {
                                selectedOverlay = overlay
                                webViewId = UUID()
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: overlay.icon)
                                        .font(.system(size: 14))
                                    Text(overlay.label)
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .frame(width: 52, height: 40)
                                .background(selectedOverlay == overlay ? Color.white.opacity(0.3) : Color.clear)
                                .foregroundStyle(.white)
                            }
                        }
                    }
                    .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))

                    // Model selector (vertical)
                    VStack(spacing: 0) {
                        ForEach(WindyModel.allCases) { model in
                            Button {
                                selectedModel = model
                                webViewId = UUID()
                            } label: {
                                Text(model.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 52, height: 32)
                                    .background(selectedModel == model ? Color.white.opacity(0.3) : Color.clear)
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .modifier(LiquidGlassRoundedModifier(cornerRadius: 10))

                    // Reload button (closes any open Windy panel)
                    Button {
                        webViewId = UUID()
                    } label: {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }

                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.top, 8)

                Spacer()
            }
        }
    }
}

// MARK: - Windy Overlay Types

enum WindyOverlay: String, CaseIterable, Identifiable {
    case wind, gust, rain, clouds, waves, temperature

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wind: "Vent"
        case .gust: "Rafales"
        case .rain: "Pluie"
        case .clouds: "Nuages"
        case .waves: "Houle"
        case .temperature: "Temp."
        }
    }

    var icon: String {
        switch self {
        case .wind: "wind"
        case .gust: "wind.circle"
        case .rain: "cloud.rain"
        case .clouds: "cloud"
        case .waves: "water.waves"
        case .temperature: "thermometer.medium"
        }
    }

    var windyParam: String {
        switch self {
        case .wind: "wind"
        case .gust: "gust"
        case .rain: "rain"
        case .clouds: "clouds"
        case .waves: "waves"
        case .temperature: "temp"
        }
    }
}

enum WindyModel: String, CaseIterable, Identifiable {
    case ecmwf, gfs, arome

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ecmwf: "ECMWF"
        case .gfs: "GFS"
        case .arome: "AROME"
        }
    }

    var windyParam: String {
        switch self {
        case .ecmwf: "ecmwf"
        case .gfs: "gfs"
        case .arome: "iconEu"
        }
    }
}

// MARK: - Windy WebView

struct WindyWebView: UIViewRepresentable {
    let latitude: Double
    let longitude: Double
    let zoom: Int
    let overlay: WindyOverlay
    let model: WindyModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        webView.navigationDelegate = context.coordinator

        loadWindy(webView: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload handled via .id() change in parent
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func loadWindy(webView: WKWebView) {
        // Load embed URL directly (not in iframe) so we can inject CSS to hide the detail panel
        let embedURL = "https://embed.windy.com/embed.html?type=map&location=coordinates&metricWind=kt&metricTemp=°C&lat=\(latitude)&lon=\(longitude)&zoom=\(zoom)&overlay=\(overlay.windyParam)&product=\(model.windyParam)&level=surface"

        if let url = URL(string: embedURL) {
            webView.load(URLRequest(url: url))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Only fix the viewport to fill the screen, don't hide any Windy UI
            let js = """
            (function() {
                var style = document.createElement('style');
                style.textContent = `
                    body, html {
                        overflow: hidden !important;
                        height: 100% !important;
                        height: 100vh !important;
                        height: 100dvh !important;
                    }
                    #map-container, .map-container, #map,
                    .leaflet-container {
                        height: 100% !important;
                        height: 100vh !important;
                        height: 100dvh !important;
                    }
                `;
                document.head.appendChild(style);
            })();
            """
            webView.evaluateJavaScript(js)
        }
    }
}

// MARK: - Windy Legend

struct WindyLegendView: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Vent (noeuds)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 3) {
                ForEach(windColors, id: \.label) { item in
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(item.color)
                            .frame(width: 22, height: 12)
                            .cornerRadius(2)
                        Text(item.label)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
    }

    private var windColors: [(label: String, color: Color)] {
        [
            ("<7", Color(red: 0.70, green: 0.93, blue: 1.00)),
            ("10", Color(red: 0.33, green: 0.85, blue: 0.92)),
            ("16", Color(red: 0.35, green: 0.89, blue: 0.52)),
            ("21", Color(red: 0.97, green: 0.90, blue: 0.33)),
            ("27", Color(red: 0.98, green: 0.67, blue: 0.23)),
            ("33", Color(red: 0.95, green: 0.22, blue: 0.26)),
            ("40", Color(red: 0.83, green: 0.20, blue: 0.67)),
            ("47", Color(red: 0.55, green: 0.24, blue: 0.78)),
            ("48+", Color(red: 0.39, green: 0.24, blue: 0.63))
        ]
    }
}

// MARK: - Helper to convert MapKit zoom to Windy zoom

extension MKCoordinateSpan {
    var windyZoom: Int {
        // Convert span to approximate Windy zoom level
        let latDelta = latitudeDelta
        if latDelta > 40 { return 3 }
        if latDelta > 20 { return 4 }
        if latDelta > 10 { return 5 }
        if latDelta > 5 { return 6 }
        if latDelta > 2 { return 7 }
        if latDelta > 1 { return 8 }
        if latDelta > 0.5 { return 9 }
        if latDelta > 0.2 { return 10 }
        if latDelta > 0.1 { return 11 }
        return 12
    }
}
