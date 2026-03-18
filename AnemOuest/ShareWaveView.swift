import SwiftUI
import Charts
import Photos

// MARK: - Wave Share Format

enum WaveShareFormat: String, CaseIterable, Identifiable {
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
        case .story: return CGSize(width: 390, height: 693)
        case .chart: return CGSize(width: 390, height: 693)
        case .square: return CGSize(width: 400, height: 400)
        case .minimal: return CGSize(width: 400, height: 280)
        case .transparent: return CGSize(width: 400, height: 220)
        }
    }
}

// MARK: - Share Wave Sheet

struct ShareWaveSheet: View {
    let buoy: WaveBuoy
    var history: [WaveHistoryPoint] = []
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: WaveShareFormat = .story
    @State private var backgroundOpacity: Double = 0.0
    @State private var savedToGallery: Bool = false
    @State private var showStyleOptions: Bool = false
    @AppStorage("shareSkin") private var selectedSkinRaw: String = ShareSkin.ocean.rawValue
    @AppStorage("shareFont") private var selectedFontRaw: String = ShareFontStyle.rounded.rawValue

    private var selectedSkin: ShareSkin {
        ShareSkin(rawValue: selectedSkinRaw) ?? .ocean
    }

    private var selectedFont: ShareFontStyle {
        ShareFontStyle(rawValue: selectedFontRaw) ?? .rounded
    }

    private var availableFormats: [WaveShareFormat] {
        if history.isEmpty {
            return WaveShareFormat.allCases.filter { $0 != .chart }
        }
        return WaveShareFormat.allCases
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Format picker
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

                // Style button
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showStyleOptions.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
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

                // Preview
                ScrollView {
                    ShareableWaveView(
                        buoy: buoy,
                        history: history,
                        format: selectedFormat,
                        skin: selectedSkin,
                        fontStyle: selectedFont,
                        backgroundOpacity: backgroundOpacity
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    .padding()
                }

                // Action buttons
                HStack(spacing: 12) {
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
    }

    private func renderImage() -> UIImage? {
        let view = ShareableWaveView(
            buoy: buoy,
            history: history,
            format: selectedFormat,
            skin: selectedSkin,
            fontStyle: selectedFont,
            backgroundOpacity: backgroundOpacity
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
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: pngData, options: nil)
            })
        } else {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }

        HapticManager.shared.closeSheet()
        Analytics.shared(type: "wave", format: selectedFormat.rawValue)
        withAnimation(.spring(response: 0.3)) {
            savedToGallery = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { savedToGallery = false }
        }
    }

    private func shareImage() {
        guard let image = renderImage() else { return }
        Analytics.shared(type: "wave", format: selectedFormat.rawValue)

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

// MARK: - Shareable Wave View

struct ShareableWaveView: View {
    let buoy: WaveBuoy
    var history: [WaveHistoryPoint] = []
    let format: WaveShareFormat
    var skin: ShareSkin = .ocean
    var fontStyle: ShareFontStyle = .rounded
    var backgroundOpacity: Double = 0.6

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMM • HH:mm"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: Date()).capitalized
    }

    private var directionCardinal: String {
        guard let dir = buoy.direction else { return "" }
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

    // MARK: - Wave Color

    private func waveColor(_ meters: Double) -> Color {
        switch meters {
        case ..<0.5: return Color(red: 0.70, green: 0.93, blue: 1.00)
        case ..<1.0: return Color(red: 0.33, green: 0.85, blue: 0.92)
        case ..<1.5: return Color(red: 0.35, green: 0.89, blue: 0.52)
        case ..<2.0: return Color(red: 0.97, green: 0.90, blue: 0.33)
        case ..<3.0: return Color(red: 0.98, green: 0.67, blue: 0.23)
        case ..<4.0: return Color(red: 0.95, green: 0.22, blue: 0.26)
        case ..<5.0: return Color(red: 0.83, green: 0.20, blue: 0.67)
        default: return Color(red: 0.55, green: 0.24, blue: 0.78)
        }
    }

    // MARK: - Story Layout (9:16)

    private var storyLayout: some View {
        ZStack {
            skin.backgroundView(windValue: buoy.hm0, windColorFn: waveColor)

            VStack(spacing: 0) {
                Spacer().frame(height: 50)

                // Logo
                HStack(spacing: 8) {
                    Image(systemName: "water.waves")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(skin.accentColor)
                    Text("Houle")
                        .font(fontStyle.font(size: 24, weight: .bold))
                        .foregroundStyle(skin.primaryTextColor)
                }

                Spacer().frame(height: 30)

                // Buoy name
                Text(buoy.name)
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

                // Main wave display
                VStack(spacing: 16) {
                    // Direction arrow
                    if let dir = buoy.direction {
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

                    // Hm0
                    if let hm0 = buoy.hm0 {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(format: "%.1f", hm0))
                                .font(fontStyle.font(size: 100, weight: .black))
                                .foregroundStyle(waveColor(hm0))
                            Text("m")
                                .font(fontStyle.font(size: 28, weight: .bold))
                                .foregroundStyle(skin.secondaryTextColor)
                        }
                    }

                    // Hmax + Period
                    HStack(spacing: 24) {
                        if let hmax = buoy.hmax {
                            VStack(spacing: 2) {
                                Text("Hmax")
                                    .font(fontStyle.font(size: 13, weight: .medium))
                                    .foregroundStyle(skin.secondaryTextColor)
                                Text(String(format: "%.1f m", hmax))
                                    .font(fontStyle.font(size: 28, weight: .bold))
                                    .foregroundStyle(waveColor(hmax))
                            }
                        }
                        if let tp = buoy.tp {
                            VStack(spacing: 2) {
                                Text("Période")
                                    .font(fontStyle.font(size: 13, weight: .medium))
                                    .foregroundStyle(skin.secondaryTextColor)
                                Text(String(format: "%.0f s", tp))
                                    .font(fontStyle.font(size: 28, weight: .bold))
                                    .foregroundStyle(skin.primaryTextColor)
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

    private var chartYMax: Double {
        let allValues = history.flatMap { point -> [Double] in
            var vals = [point.hm0]
            if let hmax = point.hmax { vals.append(hmax) }
            return vals
        }
        let maxValue = allValues.max() ?? 2
        let rounded = ceil(maxValue / 0.5) * 0.5
        return max(rounded + 0.5, 2)
    }

    private var chartYStride: Double {
        if chartYMax <= 3 { return 0.5 }
        if chartYMax <= 6 { return 1.0 }
        return 2.0
    }

    private var chartLayout: some View {
        ZStack {
            skin.backgroundView(windValue: buoy.hm0, windColorFn: waveColor)

            VStack(spacing: 0) {
                Spacer().frame(height: 44)

                // Logo
                HStack(spacing: 8) {
                    Image(systemName: "water.waves")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(skin.accentColor)
                    Text("Houle")
                        .font(fontStyle.font(size: 22, weight: .bold))
                        .foregroundStyle(skin.primaryTextColor)
                }

                Spacer().frame(height: 20)

                // Buoy name
                Text(buoy.name)
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

                // Current data row
                HStack(spacing: 20) {
                    if let dir = buoy.direction {
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

                    if let hm0 = buoy.hm0 {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.1f", hm0))
                                .font(fontStyle.font(size: 64, weight: .black))
                                .foregroundStyle(waveColor(hm0))
                            Text("m")
                                .font(fontStyle.font(size: 20, weight: .bold))
                                .foregroundStyle(skin.secondaryTextColor)
                        }
                    }

                    VStack(spacing: 6) {
                        if let hmax = buoy.hmax {
                            HStack(spacing: 4) {
                                Text(String(format: "%.1f", hmax))
                                    .font(fontStyle.font(size: 24, weight: .bold))
                                    .foregroundStyle(waveColor(hmax))
                                Text("max")
                                    .font(fontStyle.font(size: 12, weight: .medium))
                                    .foregroundStyle(skin.secondaryTextColor)
                            }
                        }
                        if let tp = buoy.tp {
                            HStack(spacing: 4) {
                                Text(String(format: "%.0fs", tp))
                                    .font(fontStyle.font(size: 18, weight: .bold))
                                    .foregroundStyle(skin.primaryTextColor)
                            }
                        }
                    }
                }

                Spacer().frame(height: 24)

                // Chart
                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        // Legend
                        HStack(spacing: 16) {
                            HStack(spacing: 5) {
                                Circle().fill(skin.chartHm0Color).frame(width: 7, height: 7)
                                Text("Hm0")
                                    .font(fontStyle.font(size: 11, weight: .medium))
                                    .foregroundStyle(skin.secondaryTextColor)
                            }
                            HStack(spacing: 5) {
                                Circle().fill(skin.chartHmaxColor).frame(width: 7, height: 7)
                                Text("Hmax")
                                    .font(fontStyle.font(size: 11, weight: .medium))
                                    .foregroundStyle(skin.secondaryTextColor)
                            }
                            Spacer()
                            Text("m")
                                .font(fontStyle.font(size: 10, weight: .medium))
                                .foregroundStyle(skin.tertiaryTextColor)
                        }
                        .padding(.horizontal, 20)

                        Chart {
                            // Area fill for Hm0
                            ForEach(history) { point in
                                AreaMark(
                                    x: .value("Time", point.timestamp),
                                    yStart: .value("Min", 0),
                                    yEnd: .value("Hm0", point.hm0),
                                    series: .value("Type", "Hm0Fill")
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [skin.chartHm0Color.opacity(0.35), skin.chartHm0Color.opacity(0.05)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.catmullRom)
                            }

                            // Hmax line
                            ForEach(history.filter { $0.hmax != nil }) { point in
                                LineMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Hmax", point.hmax!),
                                    series: .value("Type", "Hmax")
                                )
                                .foregroundStyle(skin.chartHmaxColor)
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            }

                            // Hm0 line (on top)
                            ForEach(history) { point in
                                LineMark(
                                    x: .value("Time", point.timestamp),
                                    y: .value("Hm0", point.hm0),
                                    series: .value("Type", "Hm0")
                                )
                                .foregroundStyle(skin.chartHm0Color)
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            }
                        }
                        .chartLegend(.hidden)
                        .chartYScale(domain: 0...chartYMax)
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
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
                                        Text(String(format: "%.1f", v))
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
            skin.backgroundView(windValue: buoy.hm0, windColorFn: waveColor)

            VStack(spacing: 16) {
                // Header
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "water.waves")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(skin.accentColor)
                        Text("Houle")
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

                // Buoy name
                Text(buoy.name)
                    .font(fontStyle.font(size: 24, weight: .black))
                    .foregroundStyle(skin.primaryTextColor)
                    .multilineTextAlignment(.center)

                // Wave display
                HStack(spacing: 24) {
                    if let dir = buoy.direction {
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

                    if let hm0 = buoy.hm0 {
                        VStack(spacing: 0) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.1f", hm0))
                                    .font(fontStyle.font(size: 72, weight: .black))
                                    .foregroundStyle(waveColor(hm0))
                                Text("m")
                                    .font(fontStyle.font(size: 20, weight: .bold))
                                    .foregroundStyle(skin.secondaryTextColor)
                            }

                            HStack(spacing: 16) {
                                if let hmax = buoy.hmax {
                                    HStack(spacing: 4) {
                                        Text("max")
                                            .font(fontStyle.font(size: 14, weight: .medium))
                                            .foregroundStyle(skin.secondaryTextColor)
                                        Text(String(format: "%.1f", hmax))
                                            .font(fontStyle.font(size: 24, weight: .bold))
                                            .foregroundStyle(waveColor(hmax).opacity(0.8))
                                    }
                                }
                                if let tp = buoy.tp {
                                    Text(String(format: "%.0fs", tp))
                                        .font(fontStyle.font(size: 20, weight: .bold))
                                        .foregroundStyle(skin.primaryTextColor.opacity(0.7))
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
            skin.backgroundView(windValue: buoy.hm0, windColorFn: waveColor)

            VStack(spacing: 20) {
                // Buoy name
                Text(buoy.name.uppercased())
                    .font(fontStyle.font(size: 14, weight: .bold))
                    .foregroundStyle(skin.secondaryTextColor)
                    .tracking(3)

                // Wave display
                HStack(alignment: .center, spacing: 24) {
                    if let dir = buoy.direction {
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

                    if let hm0 = buoy.hm0 {
                        VStack(spacing: 0) {
                            Text(String(format: "%.1f", hm0))
                                .font(fontStyle.font(size: 80, weight: .black))
                                .foregroundStyle(skin.primaryTextColor)
                            Text("mètres")
                                .font(fontStyle.font(size: 14, weight: .medium))
                                .foregroundStyle(skin.secondaryTextColor)
                        }
                    }

                    VStack(spacing: 6) {
                        if let hmax = buoy.hmax {
                            VStack(spacing: 0) {
                                Text(String(format: "%.1f", hmax))
                                    .font(fontStyle.font(size: 32, weight: .bold))
                                    .foregroundStyle(skin.secondaryTextColor)
                                Text("max")
                                    .font(fontStyle.font(size: 12, weight: .medium))
                                    .foregroundStyle(skin.secondaryTextColor)
                            }
                        }
                    }
                }

                // Footer
                HStack(spacing: 6) {
                    Image(systemName: "water.waves")
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
            if let dir = buoy.direction {
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
                // Buoy name
                Text(buoy.name)
                    .font(fontStyle.font(size: 18, weight: .bold))
                    .foregroundStyle(skin.primaryTextColor)
                    .shadow(color: shadowColor, radius: 3, y: 1)

                // Wave height
                if let hm0 = buoy.hm0 {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f", hm0))
                            .font(fontStyle.font(size: 56, weight: .black))
                            .foregroundStyle(waveColor(hm0))
                            .shadow(color: shadowColor, radius: 4, y: 2)
                        Text("m")
                            .font(fontStyle.font(size: 18, weight: .bold))
                            .foregroundStyle(skin.primaryTextColor)
                            .shadow(color: shadowColor, radius: 3, y: 1)

                        if let hmax = buoy.hmax {
                            Text("·")
                                .foregroundStyle(skin.primaryTextColor)
                                .shadow(color: shadowColor, radius: 2, y: 1)
                            Text(String(format: "%.1f", hmax))
                                .font(fontStyle.font(size: 28, weight: .bold))
                                .foregroundStyle(waveColor(hmax))
                                .shadow(color: shadowColor, radius: 3, y: 1)
                            Text("max")
                                .font(fontStyle.font(size: 14, weight: .medium))
                                .foregroundStyle(skin.primaryTextColor)
                                .shadow(color: shadowColor, radius: 2, y: 1)
                        }
                    }
                }

                // Date + App + Period
                HStack(spacing: 6) {
                    if let tp = buoy.tp {
                        Text(String(format: "%.0fs", tp))
                            .font(fontStyle.font(size: 11, weight: .bold))
                            .foregroundStyle(skin.primaryTextColor)
                        Text("·")
                            .foregroundStyle(skin.primaryTextColor)
                    }
                    Text(dateString)
                        .font(fontStyle.font(size: 11, weight: .medium))
                        .foregroundStyle(skin.primaryTextColor)
                    Text("·")
                        .foregroundStyle(skin.primaryTextColor)
                    Image(systemName: "water.waves")
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
}
