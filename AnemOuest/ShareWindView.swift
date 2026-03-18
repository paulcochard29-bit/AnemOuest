import SwiftUI
import Charts
import Photos

// MARK: - Share Format Enum

enum ShareFormat: String, CaseIterable, Identifiable {
    case story = "Story"
    case chart = "Graphique"
    case square = "Carré"
    case minimal = "Minimal"
    case transparent = "Transparent"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .story: return "rectangle.portrait"
        case .chart: return "chart.xyaxis.line"
        case .square: return "square"
        case .minimal: return "textformat"
        case .transparent: return "circle.dotted"
        }
    }

    var size: CGSize {
        switch self {
        case .story: return CGSize(width: 390, height: 693) // 9:16
        case .chart: return CGSize(width: 390, height: 693) // 9:16
        case .square: return CGSize(width: 400, height: 400) // 1:1
        case .minimal: return CGSize(width: 400, height: 280) // Compact
        case .transparent: return CGSize(width: 400, height: 220) // Compact
        }
    }
}

// MARK: - Share Sheet View

struct ShareWindSheet: View {
    let stationName: String
    let wind: Double?
    let gust: Double?
    let direction: Double?
    var samples: [WCChartSample] = []
    var sensorId: String = ""
    var stationSource: WindSource? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: ShareFormat = .story
    @State private var backgroundOpacity: Double = 0.0
    @State private var savedToGallery: Bool = false
    @State private var chartTimeFrame: Int = 60
    @State private var chartSamples: [WCChartSample] = []
    @State private var isLoadingChart: Bool = false
    @State private var chartError: String? = nil
    @State private var showStyleOptions: Bool = false
    @AppStorage("shareSkin") private var selectedSkinRaw: String = ShareSkin.ocean.rawValue
    @AppStorage("shareFont") private var selectedFontRaw: String = ShareFontStyle.rounded.rawValue

    private var selectedSkin: ShareSkin {
        ShareSkin(rawValue: selectedSkinRaw) ?? .ocean
    }

    private var selectedFont: ShareFontStyle {
        ShareFontStyle(rawValue: selectedFontRaw) ?? .rounded
    }

    /// Available formats - hide chart option if no samples available
    private var availableFormats: [ShareFormat] {
        let hasChartData = !samples.filter { $0.kind == .wind && $0.value.isFinite && $0.value >= 0 }.isEmpty
        if hasChartData {
            return ShareFormat.allCases
        } else {
            return ShareFormat.allCases.filter { $0 != .chart }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Format picker - scrollable (hides chart option if no data)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableFormats) { format in
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedFormat = format
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: format.icon)
                                        .font(.system(size: 18, weight: .medium))
                                    Text(format.rawValue)
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(selectedFormat == format ? .white : .primary)
                                .frame(width: 70)
                                .padding(.vertical, 10)
                                .background(
                                    selectedFormat == format
                                        ? Color.cyan
                                        : Color.primary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(4)
                .modifier(LiquidGlassRoundedModifier(cornerRadius: 14))
                .padding(.horizontal)

                // Style button (collapsed) - shows current skin + font
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showStyleOptions.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        // Current skin thumbnail
                        LinearGradient(
                            colors: selectedSkin.thumbnailColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                        Text(selectedSkin.displayName)
                            .font(.system(size: 13, weight: .medium))

                        Text("·")
                            .foregroundStyle(.tertiary)

                        Text(selectedFont.displayName)
                            .font(selectedFont.font(size: 13, weight: .medium))

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(showStyleOptions ? 90 : 0))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .modifier(LiquidGlassRoundedModifier(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                // Expandable style options
                if showStyleOptions {
                    VStack(spacing: 12) {
                        // Skin picker
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(ShareSkin.allCases) { skin in
                                    Button {
                                        withAnimation(.spring(response: 0.3)) {
                                            selectedSkinRaw = skin.rawValue
                                        }
                                    } label: {
                                        VStack(spacing: 5) {
                                            ZStack {
                                                LinearGradient(
                                                    colors: skin.thumbnailColors,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                                .frame(width: 44, height: 44)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                        .strokeBorder(
                                                            selectedSkin == skin ? Color.cyan : Color.clear,
                                                            lineWidth: 2.5
                                                        )
                                                )

                                                if selectedSkin == skin {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 14, weight: .bold))
                                                        .foregroundStyle(skin.isDark ? .white : .black)
                                                }
                                            }

                                            Text(skin.displayName)
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundStyle(selectedSkin == skin ? .primary : .secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                        }

                        // Font picker
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(ShareFontStyle.allCases) { style in
                                    Button {
                                        withAnimation(.spring(response: 0.3)) {
                                            selectedFontRaw = style.rawValue
                                        }
                                    } label: {
                                        VStack(spacing: 5) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(Color.primary.opacity(0.06))
                                                    .frame(width: 44, height: 44)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                            .strokeBorder(
                                                                selectedFont == style ? Color.cyan : Color.clear,
                                                                lineWidth: 2.5
                                                            )
                                                    )

                                                Text("Aa")
                                                    .font(style.font(size: 18, weight: .bold))
                                                    .foregroundStyle(selectedFont == style ? .primary : .secondary)
                                            }

                                            Text(style.displayName)
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundStyle(selectedFont == style ? .primary : .secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                        }

                        // Opacity slider for transparent format
                        if selectedFormat == .transparent {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Opacité du fond")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int(backgroundOpacity * 100))%")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.cyan)
                                }
                                Slider(value: $backgroundOpacity, in: 0...1, step: 0.1)
                                    .tint(.cyan)
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(8)
                    .modifier(LiquidGlassRoundedModifier(cornerRadius: 14))
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Time frame picker for chart format
                if selectedFormat == .chart {
                    HStack(spacing: 8) {
                        chartTimeButton(value: 60, label: "2h")
                        chartTimeButton(value: 36, label: "6h")
                        chartTimeButton(value: 144, label: "24h")
                        chartTimeButton(value: 288, label: "48h")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .overlay {
                        if isLoadingChart {
                            ProgressView()
                                .tint(.cyan)
                        }
                    }

                    if let error = chartError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 20)
                    }
                }

                // Preview
                ScrollView {
                    let activeSamples = selectedFormat == .chart ? chartSamples : samples
                    ShareableWindView(
                        stationName: stationName,
                        wind: wind,
                        gust: gust,
                        direction: direction,
                        format: selectedFormat,
                        skin: selectedSkin,
                        fontStyle: selectedFont,
                        backgroundOpacity: backgroundOpacity,
                        samples: activeSamples
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    .padding()
                }

                // Action buttons
                HStack(spacing: 12) {
                    // Save to gallery button (primary)
                    Button {
                        saveToGallery()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: savedToGallery ? "checkmark" : "photo.on.rectangle.angled")
                                .font(.system(size: 16, weight: .semibold))
                            Text(savedToGallery ? "Enregistré !" : "Enregistrer")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            savedToGallery ? Color.green : Color.cyan,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }

                    // Share sheet button (secondary)
                    Button {
                        shareImage()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .frame(width: 52, height: 48)
                            .background(Color.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("Partager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        HapticManager.shared.closeSheet()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            chartSamples = samples
            // If chart format is selected but no chart data, switch to story format
            let hasChartData = !samples.filter { $0.kind == .wind && $0.value.isFinite && $0.value >= 0 }.isEmpty
            if selectedFormat == .chart && !hasChartData {
                selectedFormat = .story
            }
        }
        .task(id: chartTimeFrame) {
            guard selectedFormat == .chart else { return }
            chartError = nil

            if chartTimeFrame == 60 {
                chartSamples = samples
                return
            }

            guard !sensorId.isEmpty else {
                chartError = "Pas de sensorId"
                return
            }

            // Map timeFrame picker tags to hours
            let hours: Int
            switch chartTimeFrame {
            case 36: hours = 6
            case 144: hours = 24
            case 288: hours = 48
            default: hours = 2
            }

            isLoadingChart = true
            do {
                let newSamples: [WCChartSample]
                switch stationSource {
                case .meteoFrance:
                    newSamples = try await Self.fetchMeteoFranceSamples(stationId: sensorId, hours: hours)
                case .holfuy:
                    newSamples = try await Self.fetchHolfuySamples(stationId: sensorId, hours: hours)
                case .windguru:
                    newSamples = try await Self.fetchWindguruSamples(stationId: sensorId, hours: hours)
                case .pioupiou:
                    newSamples = try await Self.fetchPioupiouSamples(stationId: sensorId, hours: hours)
                case .windsUp:
                    newSamples = Self.fetchWindsUpSamples(stationId: sensorId, hours: hours)
                case .diabox:
                    newSamples = try await Self.fetchDiaboxSamples(stationId: sensorId, hours: hours)
                default:
                    // WindCornouaille and others: use WindService
                    let result = try await WindService.fetchChartWC(sensorId: sensorId, timeFrame: chartTimeFrame)
                    newSamples = result.samples
                }
                chartSamples = newSamples
            } catch {
                chartError = "Erreur: \(error.localizedDescription)"
            }
            isLoadingChart = false
        }
    }

    @ViewBuilder
    private func chartTimeButton(value: Int, label: String) -> some View {
        Button {
            chartTimeFrame = value
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(chartTimeFrame == value ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    chartTimeFrame == value
                        ? Color.cyan
                        : Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Source-specific chart loading

    private static func fetchMeteoFranceSamples(stationId: String, hours: Int) async throws -> [WCChartSample] {
        // Strip "meteofrance_" prefix — the API expects the raw station ID
        let rawId = stationId.replacingOccurrences(of: "meteofrance_", with: "")
        let history = try await MeteoFranceService.shared.fetchHistoryFromVercel(stationId: rawId, hours: hours)
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let filtered = history.filter { $0.timestamp >= cutoff }
        return observationsToSamples(filtered.map { ($0.timestamp, $0.windSpeed, $0.windGust, $0.windDirection) })
    }

    private static func fetchHolfuySamples(stationId: String, hours: Int) async throws -> [WCChartSample] {
        let history = try await HolfuyHistoryService.shared.fetchHistory(stationId: stationId, hours: hours)
        return observationsToSamples(history.map { ($0.timestamp, $0.windSpeed, $0.gustSpeed, $0.direction) })
    }

    private static func fetchWindguruSamples(stationId: String, hours: Int) async throws -> [WCChartSample] {
        let history = try await GoWindVercelService.shared.fetchHistory(stationId: stationId, hours: hours)
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let filtered = history.filter { $0.timestamp >= cutoff }
        return observationsToSamples(filtered.map { ($0.timestamp, $0.windSpeed, $0.gustSpeed, $0.direction) })
    }

    private static func fetchPioupiouSamples(stationId: String, hours: Int) async throws -> [WCChartSample] {
        let history = try await PioupiouVercelService.shared.fetchHistoryDirect(stationId: stationId, hours: hours)
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let filtered = history.filter { $0.timestamp >= cutoff }
        return observationsToSamples(filtered.map { ($0.timestamp, $0.windSpeed, $0.gustSpeed, $0.direction) })
    }

    private static func fetchDiaboxSamples(stationId: String, hours: Int) async throws -> [WCChartSample] {
        let rawId = stationId.replacingOccurrences(of: "diabox_", with: "")
        let history = try await DiaboxService.shared.fetchHistory(stationId: rawId, hours: hours)
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let filtered = history.filter { $0.timestamp >= cutoff }
        return observationsToSamples(filtered.map { ($0.timestamp, $0.windSpeed, $0.gustSpeed, $0.direction) })
    }

    private static func fetchWindsUpSamples(stationId: String, hours: Int) -> [WCChartSample] {
        let allObs = WindsUpService.shared.getObservations(windStationId: stationId)
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let filtered = allObs.filter { $0.timestamp >= cutoff }
        return observationsToSamples(filtered.map { ($0.timestamp, $0.windSpeed, $0.gustSpeed ?? 0, $0.windDirectionDegrees ?? -1) })
    }

    private static func observationsToSamples(_ obs: [(Date, Double, Double, Double)]) -> [WCChartSample] {
        var samples: [WCChartSample] = []
        for (ts, wind, gust, dir) in obs {
            let tsKey = ts.timeIntervalSince1970
            samples.append(WCChartSample(id: "\(tsKey)_wind", t: ts, value: wind, kind: .wind))
            if gust > 0 {
                samples.append(WCChartSample(id: "\(tsKey)_gust", t: ts, value: gust, kind: .gust))
            }
            if dir >= 0 && dir <= 360 {
                samples.append(WCChartSample(id: "\(tsKey)_dir", t: ts, value: dir, kind: .dir))
            }
        }
        samples.sort { $0.t < $1.t }
        return samples
    }

    private func renderImage() -> UIImage? {
        let view = ShareableWindView(
            stationName: stationName,
            wind: wind,
            gust: gust,
            direction: direction,
            format: selectedFormat,
            skin: selectedSkin,
            fontStyle: selectedFont,
            backgroundOpacity: backgroundOpacity,
            samples: selectedFormat == .chart ? chartSamples : samples
        )

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0

        if selectedFormat == .transparent {
            renderer.isOpaque = false
        }

        return renderer.uiImage
    }

    private func saveToGallery() {
        guard let image = renderImage() else { return }

        if selectedFormat == .transparent, let pngData = image.pngData() {
            // Save as PNG to preserve transparency
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: pngData, options: nil)
            })
        } else {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }

        HapticManager.shared.closeSheet()
        Analytics.shared(type: "wind", format: selectedFormat.rawValue)
        withAnimation(.spring(response: 0.3)) {
            savedToGallery = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { savedToGallery = false }
        }
    }

    private func shareImage() {
        guard let image = renderImage() else { return }
        Analytics.shared(type: "wind", format: selectedFormat.rawValue)

        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }

            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }

            topVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Shareable Wind View

struct ShareableWindView: View {
    let stationName: String
    let wind: Double?
    let gust: Double?
    let direction: Double?
    let format: ShareFormat
    var skin: ShareSkin = .ocean
    var fontStyle: ShareFontStyle = .rounded
    var backgroundOpacity: Double = 0.6
    var samples: [WCChartSample] = []

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMM • HH:mm"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: Date()).capitalized
    }

    private var directionCardinal: String {
        guard let dir = direction else { return "" }
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSO", "SO", "OSO", "O", "ONO", "NO", "NNO"]
        let index = Int((dir + 11.25) / 22.5) % 16
        return directions[index]
    }

    var body: some View {
        Group {
            switch format {
            case .story:
                storyLayout
            case .chart:
                chartLayout
            case .square:
                squareLayout
            case .minimal:
                minimalLayout
            case .transparent:
                transparentLayout
            }
        }
        .frame(width: format.size.width, height: format.size.height)
    }

    // MARK: - Story Layout (9:16)

    private var storyLayout: some View {
        ZStack {
            skin.backgroundView(windValue: wind, windColorFn: windColor)

            VStack(spacing: 0) {
                Spacer().frame(height: 50)

                // Logo
                HStack(spacing: 8) {
                    Image(systemName: "wind")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(skin.accentColor)
                    Text("Le Vent")
                        .font(fontStyle.font(size: 24, weight: .bold))
                        .foregroundStyle(skin.primaryTextColor)
                }

                Spacer().frame(height: 30)

                // Station name
                Text(stationName)
                    .font(fontStyle.font(size: 28, weight: .black))
                    .foregroundStyle(skin.primaryTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // Date
                Text(dateString)
                    .font(fontStyle.font(size: 14, weight: .medium))
                    .foregroundStyle(skin.secondaryTextColor)
                    .padding(.top, 8)

                Spacer().frame(height: 40)

                // Main wind display
                if let windVal = wind {
                    VStack(spacing: 16) {
                        // Direction arrow
                        if let dir = direction {
                            VStack(spacing: 8) {
                                Image(systemName: "location.north.fill")
                                    .font(.system(size: 50, weight: .bold))
                                    .foregroundStyle(skin.primaryTextColor)
                                    .rotationEffect(.degrees(dir + 180))
                                Text(directionCardinal)
                                    .font(fontStyle.font(size: 18, weight: .bold))
                                    .foregroundStyle(skin.secondaryTextColor)
                            }
                        }

                        // Wind speed
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(WindUnit.convertValue(windVal))")
                                .font(fontStyle.font(size: 100, weight: .black))
                                .foregroundStyle(windColor(windVal))
                            Text(WindUnit.current.symbol)
                                .font(fontStyle.font(size: 28, weight: .bold))
                                .foregroundStyle(skin.secondaryTextColor)
                        }

                        // Gusts
                        if let gustVal = gust, gustVal > windVal {
                            HStack(spacing: 6) {
                                Text("Rafales")
                                    .font(fontStyle.font(size: 16, weight: .medium))
                                    .foregroundStyle(skin.secondaryTextColor)
                                Text("\(WindUnit.convertValue(gustVal))")
                                    .font(fontStyle.font(size: 32, weight: .bold))
                                    .foregroundStyle(windColor(gustVal))
                                Text(WindUnit.current.symbol)
                                    .font(fontStyle.font(size: 16, weight: .medium))
                                    .foregroundStyle(skin.secondaryTextColor)
                            }
                        }
                    }
                }

                Spacer()

                // Footer
                Text("Propulsé par l'app Le Vent")
                    .font(fontStyle.font(size: 11, weight: .medium))
                    .foregroundStyle(skin.tertiaryTextColor)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Chart Layout (9:16 with graph)

    private var chartWindSamples: [WCChartSample] {
        samples.filter { $0.kind == .wind && $0.value.isFinite && $0.value >= 0 && $0.value <= 80 }
    }

    private var chartGustSamples: [WCChartSample] {
        samples.filter { $0.kind == .gust && $0.value.isFinite && $0.value >= 0 && $0.value <= 80 }
    }

    private var chartYMax: Double {
        let allValues = samples.filter {
            ($0.kind == .wind || $0.kind == .gust) &&
            $0.value.isFinite && $0.value >= 0 && $0.value <= 80
        }.map(\.value)
        let maxValue = allValues.max() ?? 20
        let rounded = ceil(maxValue / 5) * 5
        return max(rounded + 5, 20)
    }

    private var chartYStride: Double {
        if chartYMax <= 30 { return 5 }
        return 10
    }

    private var chartLayout: some View {
        ZStack {
            skin.backgroundView(windValue: wind, windColorFn: windColor)

            VStack(spacing: 0) {
                Spacer().frame(height: 44)

                // Logo
                HStack(spacing: 8) {
                    Image(systemName: "wind")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(skin.accentColor)
                    Text("Le Vent")
                        .font(fontStyle.font(size: 22, weight: .bold))
                        .foregroundStyle(skin.primaryTextColor)
                }

                Spacer().frame(height: 20)

                // Station name
                Text(stationName)
                    .font(fontStyle.font(size: 24, weight: .black))
                    .foregroundStyle(skin.primaryTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // Date
                Text(dateString)
                    .font(fontStyle.font(size: 13, weight: .medium))
                    .foregroundStyle(skin.secondaryTextColor)
                    .padding(.top, 6)

                Spacer().frame(height: 20)

                // Current wind + direction row
                if let windVal = wind {
                    HStack(spacing: 20) {
                        if let dir = direction {
                            VStack(spacing: 4) {
                                Image(systemName: "location.north.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(skin.primaryTextColor)
                                    .rotationEffect(.degrees(dir + 180))
                                Text(directionCardinal)
                                    .font(fontStyle.font(size: 13, weight: .bold))
                                    .foregroundStyle(skin.secondaryTextColor)
                            }
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(WindUnit.convertValue(windVal))")
                                .font(fontStyle.font(size: 64, weight: .black))
                                .foregroundStyle(windColor(windVal))
                            Text(WindUnit.current.symbol)
                                .font(fontStyle.font(size: 20, weight: .bold))
                                .foregroundStyle(skin.secondaryTextColor)
                        }

                        if let gustVal = gust, gustVal > windVal {
                            VStack(spacing: 2) {
                                Text("\(WindUnit.convertValue(gustVal))")
                                    .font(fontStyle.font(size: 28, weight: .bold))
                                    .foregroundStyle(windColor(gustVal))
                                Text("raf.")
                                    .font(fontStyle.font(size: 12, weight: .medium))
                                    .foregroundStyle(skin.secondaryTextColor)
                            }
                        }
                    }
                }

                Spacer().frame(height: 24)

                // Chart
                if !chartWindSamples.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        // Legend
                        HStack(spacing: 16) {
                            HStack(spacing: 5) {
                                Circle().fill(skin.chartWindColor).frame(width: 7, height: 7)
                                Text("Vent")
                                    .font(fontStyle.font(size: 11, weight: .medium))
                                    .foregroundStyle(skin.secondaryTextColor)
                            }
                            if !chartGustSamples.isEmpty {
                                HStack(spacing: 5) {
                                    Circle().fill(skin.chartGustColor).frame(width: 7, height: 7)
                                    Text("Rafales")
                                        .font(fontStyle.font(size: 11, weight: .medium))
                                        .foregroundStyle(skin.secondaryTextColor)
                                }
                            }
                            Spacer()
                            Text(WindUnit.current.symbol)
                                .font(fontStyle.font(size: 10, weight: .medium))
                                .foregroundStyle(skin.tertiaryTextColor)
                        }
                        .padding(.horizontal, 20)

                        // Swift Charts graph
                        Chart {
                            // Area fill for wind
                            ForEach(chartWindSamples) { sample in
                                AreaMark(
                                    x: .value("Time", sample.t),
                                    yStart: .value("Min", 0),
                                    yEnd: .value("Knots", sample.value),
                                    series: .value("Type", "WindFill")
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [skin.chartWindColor.opacity(0.35), skin.chartWindColor.opacity(0.05)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.catmullRom)
                            }

                            // Area fill for gusts
                            ForEach(chartGustSamples) { sample in
                                AreaMark(
                                    x: .value("Time", sample.t),
                                    yStart: .value("Min", 0),
                                    yEnd: .value("Knots", sample.value),
                                    series: .value("Type", "GustFill")
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [skin.chartGustColor.opacity(0.25), skin.chartGustColor.opacity(0.03)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.catmullRom)
                            }

                            // Gust line
                            ForEach(chartGustSamples) { sample in
                                LineMark(
                                    x: .value("Time", sample.t),
                                    y: .value("Knots", sample.value),
                                    series: .value("Type", "Rafales")
                                )
                                .foregroundStyle(skin.chartGustColor)
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            }

                            // Wind line (on top)
                            ForEach(chartWindSamples) { sample in
                                LineMark(
                                    x: .value("Time", sample.t),
                                    y: .value("Knots", sample.value),
                                    series: .value("Type", "Vent")
                                )
                                .foregroundStyle(skin.chartWindColor)
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            }
                        }
                        .chartLegend(.hidden)
                        .chartYScale(domain: 0...chartYMax)
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(skin.chartGridColor)
                                AxisValueLabel(format: .dateTime.hour().minute())
                                    .font(fontStyle.font(size: 10, weight: .medium))
                                    .foregroundStyle(skin.chartLabelColor)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .trailing, values: .stride(by: chartYStride)) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(skin.chartGridColor)
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text("\(Int(v))")
                                            .font(fontStyle.font(size: 10, weight: .medium))
                                            .foregroundStyle(skin.chartLabelColor)
                                    }
                                }
                            }
                        }
                        .frame(height: 200)
                        .padding(.horizontal, 16)
                        .drawingGroup()
                    }
                } else {
                    Text("Aucune donnée graphique")
                        .font(fontStyle.font(size: 14, weight: .medium))
                        .foregroundStyle(skin.secondaryTextColor)
                        .frame(height: 200)
                }

                Spacer()

                // Footer
                Text("Propulsé par l'app Le Vent")
                    .font(fontStyle.font(size: 11, weight: .medium))
                    .foregroundStyle(skin.tertiaryTextColor)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Square Layout (1:1)

    private var squareLayout: some View {
        ZStack {
            skin.backgroundView(windValue: wind, windColorFn: windColor)

            VStack(spacing: 16) {
                // Header
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "wind")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(skin.accentColor)
                        Text("Le Vent")
                            .font(fontStyle.font(size: 16, weight: .bold))
                            .foregroundStyle(skin.primaryTextColor)
                    }
                    Spacer()
                    Text(dateString)
                        .font(fontStyle.font(size: 11, weight: .medium))
                        .foregroundStyle(skin.secondaryTextColor)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer()

                // Station
                Text(stationName)
                    .font(fontStyle.font(size: 24, weight: .black))
                    .foregroundStyle(skin.primaryTextColor)
                    .multilineTextAlignment(.center)

                // Wind display
                if let windVal = wind {
                    HStack(spacing: 24) {
                        // Direction
                        if let dir = direction {
                            VStack(spacing: 4) {
                                Image(systemName: "location.north.fill")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundStyle(skin.primaryTextColor)
                                    .rotationEffect(.degrees(dir + 180))
                                Text(directionCardinal)
                                    .font(fontStyle.font(size: 14, weight: .bold))
                                    .foregroundStyle(skin.secondaryTextColor)
                            }
                        }

                        // Speed
                        VStack(spacing: 0) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(WindUnit.convertValue(windVal))")
                                    .font(fontStyle.font(size: 72, weight: .black))
                                    .foregroundStyle(windColor(windVal))
                                Text(WindUnit.current.symbol)
                                    .font(fontStyle.font(size: 20, weight: .bold))
                                    .foregroundStyle(skin.secondaryTextColor)
                            }

                            if let gustVal = gust, gustVal > windVal {
                                HStack(spacing: 4) {
                                    Text("raf.")
                                        .font(fontStyle.font(size: 14, weight: .medium))
                                        .foregroundStyle(skin.secondaryTextColor)
                                    Text("\(WindUnit.convertValue(gustVal))")
                                        .font(fontStyle.font(size: 24, weight: .bold))
                                        .foregroundStyle(windColor(gustVal).opacity(0.8))
                                }
                            }
                        }
                    }
                }

                Spacer()

                // Footer
                Text("Propulsé par l'app Le Vent")
                    .font(fontStyle.font(size: 10, weight: .medium))
                    .foregroundStyle(skin.tertiaryTextColor)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Minimal Layout

    private var minimalLayout: some View {
        ZStack {
            skin.backgroundView(windValue: wind, windColorFn: windColor)

            VStack(spacing: 20) {
                // Station name
                Text(stationName.uppercased())
                    .font(fontStyle.font(size: 14, weight: .bold))
                    .foregroundStyle(skin.secondaryTextColor)
                    .tracking(3)

                // Wind display
                if let windVal = wind {
                    HStack(alignment: .center, spacing: 24) {
                        // Direction
                        if let dir = direction {
                            VStack(spacing: 6) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(skin.primaryTextColor)
                                    .rotationEffect(.degrees(dir + 180))
                                Text(directionCardinal)
                                    .font(fontStyle.font(size: 12, weight: .bold))
                                    .foregroundStyle(skin.secondaryTextColor)
                            }
                        }

                        // Speed
                        VStack(spacing: 0) {
                            Text("\(Int(round(windVal)))")
                                .font(fontStyle.font(size: 80, weight: .black))
                                .foregroundStyle(skin.primaryTextColor)
                            Text("nœuds")
                                .font(fontStyle.font(size: 14, weight: .medium))
                                .foregroundStyle(skin.secondaryTextColor)
                        }

                        // Gusts
                        if let gustVal = gust, gustVal > windVal {
                            VStack(spacing: 6) {
                                Text("\(Int(round(gustVal)))")
                                    .font(fontStyle.font(size: 32, weight: .bold))
                                    .foregroundStyle(skin.secondaryTextColor)
                                Text("raf.")
                                    .font(fontStyle.font(size: 12, weight: .medium))
                                    .foregroundStyle(skin.secondaryTextColor)
                            }
                        }
                    }
                }

                // Footer
                HStack(spacing: 6) {
                    Image(systemName: "wind")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(skin.accentColor)
                    Text("Le Vent")
                        .font(fontStyle.font(size: 11, weight: .medium))
                        .foregroundStyle(skin.tertiaryTextColor)
                }
            }
            .padding(24)
        }
    }

    // MARK: - Transparent Layout

    private var transparentLayout: some View {
        let shadowColor: Color = skin.isDark ? .black.opacity(0.8) : .white.opacity(0.6)

        return HStack(spacing: 16) {
            // Direction arrow
            if let dir = direction {
                VStack(spacing: 4) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(skin.primaryTextColor)
                        .shadow(color: shadowColor, radius: 4, y: 2)
                        .rotationEffect(.degrees(dir + 180))
                    Text(directionCardinal)
                        .font(fontStyle.font(size: 14, weight: .bold))
                        .foregroundStyle(skin.primaryTextColor)
                        .shadow(color: shadowColor, radius: 3, y: 1)
                }
                .frame(width: 70)
            }

            // Main content
            VStack(alignment: .leading, spacing: 8) {
                // Station
                Text(stationName)
                    .font(fontStyle.font(size: 18, weight: .bold))
                    .foregroundStyle(skin.primaryTextColor)
                    .shadow(color: shadowColor, radius: 3, y: 1)

                // Wind speed
                if let windVal = wind {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(WindUnit.convertValue(windVal))")
                            .font(fontStyle.font(size: 56, weight: .black))
                            .foregroundStyle(windColor(windVal))
                            .shadow(color: shadowColor, radius: 4, y: 2)
                        Text(WindUnit.current.symbol)
                            .font(fontStyle.font(size: 18, weight: .bold))
                            .foregroundStyle(skin.primaryTextColor)
                            .shadow(color: shadowColor, radius: 3, y: 1)

                        if let gustVal = gust, gustVal > windVal {
                            Text("•")
                                .foregroundStyle(skin.primaryTextColor)
                                .shadow(color: shadowColor, radius: 2, y: 1)
                            Text("\(WindUnit.convertValue(gustVal))")
                                .font(fontStyle.font(size: 28, weight: .bold))
                                .foregroundStyle(windColor(gustVal))
                                .shadow(color: shadowColor, radius: 3, y: 1)
                            Text("raf")
                                .font(fontStyle.font(size: 14, weight: .medium))
                                .foregroundStyle(skin.primaryTextColor)
                                .shadow(color: shadowColor, radius: 2, y: 1)
                        }
                    }
                }

                // Date + App
                HStack(spacing: 6) {
                    Text(dateString)
                        .font(fontStyle.font(size: 11, weight: .medium))
                        .foregroundStyle(skin.primaryTextColor)
                    Text("•")
                        .foregroundStyle(skin.primaryTextColor)
                    Image(systemName: "wind")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(skin.accentColor)
                        .shadow(color: skin.accentColor.opacity(0.5), radius: 4)
                    Text("Le Vent")
                        .font(fontStyle.font(size: 11, weight: .medium))
                        .foregroundStyle(skin.primaryTextColor)
                }
                .shadow(color: shadowColor, radius: 2, y: 1)
            }

            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    skin.isDark
                        ? Color.black.opacity(backgroundOpacity)
                        : Color.white.opacity(backgroundOpacity)
                )
        )
    }

    // MARK: - Wind Color

    private func windColor(_ knots: Double) -> Color {
        switch knots {
        case ..<7: return Color(red: 0.70, green: 0.93, blue: 1.00)
        case ..<11: return Color(red: 0.33, green: 0.85, blue: 0.92)
        case ..<17: return Color(red: 0.35, green: 0.89, blue: 0.52)
        case ..<22: return Color(red: 0.97, green: 0.90, blue: 0.33)
        case ..<28: return Color(red: 0.98, green: 0.67, blue: 0.23)
        case ..<34: return Color(red: 0.95, green: 0.22, blue: 0.26)
        case ..<41: return Color(red: 0.83, green: 0.20, blue: 0.67)
        case ..<48: return Color(red: 0.55, green: 0.24, blue: 0.78)
        default: return Color(red: 0.39, green: 0.24, blue: 0.63)
        }
    }
}
