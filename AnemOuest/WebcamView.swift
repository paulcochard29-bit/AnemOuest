import SwiftUI
import Combine
import UIKit
import AVKit
import WebKit

// MARK: - Webcam List View

struct WebcamListView: View {
    let webcams: [Webcam]
    @State private var selectedWebcam: Webcam?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(webcams) { webcam in
                        WebcamCard(webcam: webcam)
                            .onTapGesture {
                                HapticManager.shared.openSheet()
                                selectedWebcam = webcam
                                Analytics.webcamViewed(id: webcam.id)
                            }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Webcams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        HapticManager.shared.closeSheet()
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .fullScreenCover(item: $selectedWebcam) { webcam in
                WebcamFullScreenView(webcam: webcam)
            }
        }
    }
}

// MARK: - Webcam Card

struct WebcamCard: View {
    let webcam: Webcam
    @State private var imageData: Data?
    @State private var isLoading = true
    @State private var loadError = false
    @State private var isPanoramic = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image container
            ZStack {
                Rectangle()
                    .fill(Color(.systemGray5))

                if isLoading {
                    // Shimmer placeholder while loading
                    ShimmerView()
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary.opacity(0.4))
                        )
                } else if loadError {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Indisponible")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else if let data = imageData, let uiImage = UIImage(data: data) {
                    GeometryReader { geo in
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                }

                // Badges overlay
                if !isLoading && !loadError {
                    VStack {
                        HStack {
                            // Live badge
                            if WebcamService.shared.hasLiveStream(webcam) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 6, height: 6)
                                    Text("LIVE")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.red.opacity(0.8), in: Capsule())
                            }

                            Spacer()

                            // Panoramic indicator
                            if isPanoramic {
                                Label("360°", systemImage: "pano")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.5), in: Capsule())
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
            .frame(height: 180)

            // Info bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(webcam.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(webcam.location)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Source badge
                Text(webcam.source)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5), in: Capsule())
            }
            .padding(12)
            .background(Color(.systemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        isLoading = true
        loadError = false

        // Use server-side thumbnail (400px, quality 50) for card view
        let storageUrl = WebcamService.shared.thumbnailImageUrl(for: webcam)

        // Step 1: Show cached image immediately (fast path)
        let cachedData = await WebcamImageCache.shared.loadThumbnail(from: storageUrl)
        if let data = cachedData {
            imageData = data
            if let image = UIImage(data: data) {
                isPanoramic = image.size.width > image.size.height * 2
            }
            isLoading = false
        }

        // Step 2: Fetch fresh image from network to update preview
        if let fresh = await WebcamImageCache.shared.fetchFreshThumbnail(from: storageUrl) {
            if fresh.data != cachedData {
                imageData = fresh.data
                if let image = UIImage(data: fresh.data) {
                    isPanoramic = image.size.width > image.size.height * 2
                }
            }
            isLoading = false
        } else if cachedData == nil {
            // No cache and no network - try fallback URL
            let fallbackUrl = WebcamService.shared.fallbackImageUrl(for: webcam)
            if let data = await WebcamImageCache.shared.loadThumbnail(from: fallbackUrl) {
                imageData = data
                if let image = UIImage(data: data) {
                    isPanoramic = image.size.width > image.size.height * 2
                }
                isLoading = false
            } else {
                isLoading = false
                loadError = true
            }
        }
    }
}

// MARK: - Webcam Full Screen View

struct WebcamFullScreenView: View {
    let webcam: Webcam
    @Environment(\.dismiss) private var dismiss
    @State private var imageData: Data?
    @State private var isLoading = true
    @State private var loadError = false
    @State private var lastRefresh = Date()
    @State private var imageSize: CGSize = .zero
    @State private var imageTimestamp: Date?
    @State private var isLiveStreaming = false
    @State private var player: AVPlayer?
    @State private var isFullscreen = false
    @State private var youtubeError = false
    @State private var isPulsing = false

    // Timeline state
    @State private var timeline: [WebcamService.TimelineEntry] = []
    @State private var selectedTimelineIndex: Int = -1 // -1 = live
    @State private var isLoadingTimeline = false

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // Check if webcam has a live stream
    private var hasLiveStream: Bool {
        WebcamService.shared.hasLiveStream(webcam)
    }

    // Check if stream is YouTube (needs WKWebView)
    private var isYouTube: Bool {
        WebcamService.shared.isYouTubeStream(webcam)
    }

    // Detect if image is panoramic (width > 2x height)
    private var isPanoramic: Bool {
        imageSize.width > imageSize.height * 2
    }

    // All webcams now support history (stored on our server)
    private var supportsHistory: Bool {
        WebcamService.shared.supportsHistory(webcam)
    }

    // Currently viewing live mode (not history selection)
    private var isViewingLive: Bool {
        selectedTimelineIndex < 0 || timeline.isEmpty
    }

    // Check if the actual image is recent (< 45 min) - for status display
    private var isImageActuallyRecent: Bool {
        guard let timestamp = imageTimestamp else { return false }
        let elapsed = -timestamp.timeIntervalSinceNow
        return elapsed < 2700 // 45 minutes (webcams update every 30 min)
    }

    // Selected timeline entry (nil if viewing live)
    private var selectedEntry: WebcamService.TimelineEntry? {
        guard selectedTimelineIndex >= 0, selectedTimelineIndex < timeline.count else { return nil }
        return timeline[selectedTimelineIndex]
    }

    // Format selected entry time for display
    private var historyLabel: String {
        guard let entry = selectedEntry else { return "En direct" }
        let date = entry.date

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")

        // Check if same day
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return "Hier \(formatter.string(from: date))"
        } else {
            formatter.dateFormat = "EEE HH:mm"
            return formatter.string(from: date)
        }
    }

    // Format real image timestamp for status display
    private var imageTimeLabel: String {
        guard let timestamp = imageTimestamp else { return "Heure inconnue" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")

        if Calendar.current.isDateInToday(timestamp) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: timestamp)
        } else if Calendar.current.isDateInYesterday(timestamp) {
            formatter.dateFormat = "HH:mm"
            return "Hier " + formatter.string(from: timestamp)
        } else {
            formatter.dateFormat = "E HH:mm"
            return formatter.string(from: timestamp)
        }
    }

    // Format elapsed time since image
    private var imageAgeLabel: String {
        guard let timestamp = imageTimestamp else { return "" }
        let elapsed = Int(-timestamp.timeIntervalSinceNow)

        if elapsed < 0 || elapsed < 120 {
            return "à l'instant"
        } else if elapsed < 3600 {
            return "il y a \(elapsed / 60) min"
        } else if elapsed < 86400 {
            let hours = elapsed / 3600
            return "il y a \(hours)h"
        } else {
            let days = elapsed / 86400
            return "il y a \(days)j"
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Live stream or Image
            if isLiveStreaming && isYouTube && !youtubeError, let embedUrl = WebcamService.shared.youTubeEmbedUrl(for: webcam) {
                YouTubePlayerView(embedUrl: embedUrl, onError: {
                    youtubeError = true
                })
                .ignoresSafeArea()
            } else if isLiveStreaming && youtubeError {
                // YouTube error fallback - offer to open externally
                VStack(spacing: 16) {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Ce live ne peut pas être intégré")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))

                    Button {
                        if let url = WebcamService.shared.liveStreamUrl(for: webcam),
                           let youtubeUrl = URL(string: url) {
                            UIApplication.shared.open(youtubeUrl)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.forward.app")
                            Text("Ouvrir dans YouTube")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .clipShape(Capsule())
                    }
                    .padding(.top, 8)
                }
            } else if isLiveStreaming, let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if isLoading && imageData == nil {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            } else if loadError && imageData == nil {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Webcam indisponible")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                }
            } else if let data = imageData, let uiImage = UIImage(data: data) {
                // Zoomable image view (pinch-to-zoom, double-tap, pan)
                ZoomableImageView(image: uiImage, isPanoramic: isPanoramic)
            }

            // Overlay controls (hidden in fullscreen mode)
            if !isFullscreen {
                VStack {
                    // Top bar
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(webcam.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)

                            HStack(spacing: 6) {
                                Text(webcam.location)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.7))

                                Text("•")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white.opacity(0.4))

                                Text(webcam.source)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.white.opacity(0.15), in: Capsule())

                                // Show history indicator when navigating timeline
                                if !isViewingLive {
                                    Text("•")
                                        .foregroundStyle(.orange)
                                    Text(historyLabel)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.orange)
                                }
                                // Show warning when image is stale in live mode
                                else if !isLoading && !isImageActuallyRecent && imageTimestamp != nil {
                                    Text("•")
                                        .foregroundStyle(.orange)
                                    Text(imageAgeLabel)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        Spacer()

                        // Live stream toggle (when available)
                        if hasLiveStream {
                            Button(action: {
                                HapticManager.shared.medium()
                                toggleLiveStream()
                            }) {
                                HStack(spacing: 8) {
                                    if isLiveStreaming {
                                        // Streaming: show stop button
                                        Image(systemName: "stop.fill")
                                            .font(.system(size: 10))
                                        Text("Arrêter")
                                            .font(.system(size: 13, weight: .semibold))
                                    } else {
                                        // Not streaming: show play button with pulsing dot
                                        ZStack {
                                            // Outer pulsing circle
                                            Circle()
                                                .fill(Color.white.opacity(0.3))
                                                .frame(width: 18, height: 18)
                                                .scaleEffect(isPulsing ? 1.4 : 1.0)
                                                .opacity(isPulsing ? 0 : 0.6)
                                            // Inner solid dot
                                            Circle()
                                                .fill(Color.white)
                                                .frame(width: 8, height: 8)
                                        }
                                        .onAppear {
                                            isPulsing = false
                                            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                                                isPulsing = true
                                            }
                                        }
                                        .onDisappear {
                                            isPulsing = false
                                        }
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 11))
                                        Text("Live")
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(isLiveStreaming ? Color.gray.opacity(0.6) : Color.red)
                                )
                                .shadow(color: isLiveStreaming ? .clear : .red.opacity(0.5), radius: 8, y: 2)
                            }
                        }

                        // Fullscreen button (when live streaming)
                        if isLiveStreaming {
                            Button(action: {
                                HapticManager.shared.light()
                                enterFullscreen()
                            }) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(.white.opacity(0.25), in: Circle())
                            }
                        }

                        Button(action: {
                            HapticManager.shared.closeSheet()
                            stopLiveStream()
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.black.opacity(0.6), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )

                    Spacer()

                    // Bottom bar with timeline player
                    VStack(spacing: 12) {
                        // Timeline player (only for supported sources, hidden during live stream)
                        if supportsHistory && !isLiveStreaming {
                            if !timeline.isEmpty {
                                WebcamTimelinePlayer(
                                    timeline: timeline,
                                    selectedIndex: $selectedTimelineIndex,
                                    isLoading: isLoading,
                                    onSelectEntry: { entry in
                                        HapticManager.shared.light()
                                        Task { await refreshImage(timestamp: entry?.timestamp, entryUrl: entry?.url) }
                                    }
                                )
                                .padding(.horizontal)
                            } else if isLoadingTimeline {
                                // Loading indicator while fetching timeline
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                    Text("Chargement historique...")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                .frame(height: 44)
                                .padding(.horizontal)
                            } else {
                                // No timeline available - show message
                                HStack(spacing: 8) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 12))
                                    Text("Historique indisponible")
                                        .font(.system(size: 12))
                                }
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(height: 44)
                                .padding(.horizontal)
                            }
                        }

                        // Bottom controls
                        HStack {
                            // Status indicator with real timestamp
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    if isLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.white)
                                        Text("Chargement...")
                                            .font(.system(size: 12))
                                    } else if isImageActuallyRecent {
                                        // Image is actually recent (< 45 min)
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 8, height: 8)
                                        Text(imageTimeLabel)
                                            .font(.system(size: 14, weight: .semibold))
                                        Text(imageAgeLabel)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.5))
                                    } else {
                                        // Image is old
                                        Circle()
                                            .fill(.orange)
                                            .frame(width: 8, height: 8)
                                        Text(imageTimeLabel)
                                            .font(.system(size: 14, weight: .semibold))
                                        Text(imageAgeLabel)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.orange.opacity(0.8))
                                    }
                                }
                                .foregroundStyle(.white.opacity(0.9))

                                // Zoom hint
                                if !isLoading && !isLiveStreaming {
                                    HStack(spacing: 3) {
                                        Image(systemName: "hand.pinch")
                                            .font(.system(size: 9))
                                        Text("Pincer pour zoomer")
                                            .font(.system(size: 9))
                                    }
                                    .foregroundStyle(.white.opacity(0.35))
                                }
                            }

                            Spacer()

                            // Live button (when viewing history)
                            if !isViewingLive {
                                Button(action: {
                                    HapticManager.shared.medium()
                                    selectedTimelineIndex = -1
                                    Task { await refreshImage(timestamp: nil) }
                                }) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 8, height: 8)
                                        Text("En direct")
                                    }
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(.green.opacity(0.3), in: Capsule())
                                }
                            } else {
                                // Manual refresh button
                                Button(action: {
                                    HapticManager.shared.refresh()
                                    Task { await refreshImage(timestamp: nil) }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Actualiser")
                                    }
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(.white.opacity(0.2), in: Capsule())
                                }
                                .disabled(isLoading)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .padding(.top, 12)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )
                }
                .transition(.opacity)
            }

            // Fullscreen floating exit button
            if isFullscreen {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            HapticManager.shared.light()
                            exitFullscreen()
                        }) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.black.opacity(0.5), in: Circle())
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
        }
        .task {
            // Load timeline in parallel with first image
            async let imageTask: () = refreshImage(timestamp: nil)
            async let timelineTask: () = loadTimeline()
            _ = await (imageTask, timelineTask)
        }
        .onReceive(timer) { _ in
            // Only auto-refresh when viewing live (not history)
            if isViewingLive && !isLiveStreaming {
                Task { await refreshImage(timestamp: nil) }
            }
        }
    }

    private func loadTimeline() async {
        guard supportsHistory else { return }

        await MainActor.run { isLoadingTimeline = true }

        let entries = await WebcamService.shared.fetchTimeline(for: webcam)

        await MainActor.run {
            self.timeline = entries
            self.isLoadingTimeline = false
        }
    }

    private func refreshImage(timestamp: Int?, entryUrl: String? = nil) async {
        isLoading = true

        // Build URL based on whether we're viewing history or live
        let imageUrl: String
        let isHistory = timestamp != nil && supportsHistory

        if let directUrl = entryUrl, timestamp != nil {
            // Use direct blob URL from timeline entry (works for HLS webcams)
            imageUrl = directUrl
        } else if let ts = timestamp {
            imageUrl = WebcamService.shared.imageUrl(for: webcam, timestamp: ts)
        } else {
            imageUrl = WebcamService.shared.freshImageUrl(for: webcam)
        }

        // Use cache for loading
        if let result = await WebcamImageCache.shared.loadImage(from: imageUrl, isHistory: isHistory) {
            await MainActor.run {
                self.imageData = result.data
                self.imageSize = result.size
                // Use HTTP header timestamp, fallback to timeline entry timestamp
                self.imageTimestamp = result.timestamp ?? (timestamp != nil ? Date(timeIntervalSince1970: Double(timestamp!)) : nil)
                self.isLoading = false
                self.loadError = false
                self.lastRefresh = Date()
            }
        } else if !isHistory {
            // Fallback to original URL for live view only
            let fallbackUrl = WebcamService.shared.fallbackImageUrl(for: webcam)
            if let result = await WebcamImageCache.shared.loadImage(from: fallbackUrl) {
                await MainActor.run {
                    self.imageData = result.data
                    self.imageSize = result.size
                    self.imageTimestamp = result.timestamp
                    self.isLoading = false
                    self.loadError = false
                    self.lastRefresh = Date()
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                    self.loadError = imageData == nil
                }
            }
        } else {
            await MainActor.run {
                self.isLoading = false
                self.loadError = imageData == nil
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "À l'instant" }
        if seconds < 60 { return "Il y a \(seconds)s" }
        return "Il y a \(seconds / 60)min"
    }

    // MARK: - Live Stream Functions

    private func toggleLiveStream() {
        if isLiveStreaming {
            stopLiveStream()
        } else {
            startLiveStream()
        }
    }

    private func startLiveStream() {
        guard let streamUrlString = WebcamService.shared.liveStreamUrl(for: webcam) else { return }

        // YouTube streams are handled by WKWebView, no AVPlayer needed
        if isYouTube {
            isLiveStreaming = true
            Log.debug("Started YouTube live stream: \(streamUrlString)")
            return
        }

        guard let streamUrl = URL(string: streamUrlString) else { return }

        // Configure audio session to not interrupt other audio (webcam streams have no meaningful audio)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Log.error("Audio session config failed: \(error)")
        }

        // Create and configure player
        let playerItem = AVPlayerItem(url: streamUrl)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        newPlayer.isMuted = true // Mute video (no useful audio)

        // Start playback
        player = newPlayer
        isLiveStreaming = true
        newPlayer.play()

        Log.debug("Started live stream: \(streamUrlString)")
    }

    private func stopLiveStream() {
        if isFullscreen {
            exitFullscreen()
        }
        player?.pause()
        player = nil
        isLiveStreaming = false
    }

    // MARK: - Fullscreen with Landscape

    private func enterFullscreen() {
        AppDelegate.allowLandscape = true
        withAnimation(.easeInOut(duration: 0.25)) {
            isFullscreen = true
        }
        // Tell UIKit landscape is now allowed BEFORE requesting rotation
        setNeedsUpdateOfSupportedInterfaceOrientations()
        // Force landscape rotation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscapeRight)
                windowScene.requestGeometryUpdate(geometryPreferences) { error in
                    Log.error("Orientation change failed: \(error)")
                }
            }
        }
    }

    private func exitFullscreen() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isFullscreen = false
        }
        // Tell UIKit to update supported orientations, then request portrait
        setNeedsUpdateOfSupportedInterfaceOrientations()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
                windowScene.requestGeometryUpdate(geometryPreferences) { error in
                    Log.error("Orientation change failed: \(error)")
                }
            }
        }
        // Re-lock to portrait after rotation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            AppDelegate.allowLandscape = false
        }
    }

    private func setNeedsUpdateOfSupportedInterfaceOrientations() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            for window in windowScene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}

// MARK: - Compact Webcam Strip (for bottom panel)

struct WebcamStrip: View {
    let webcams: [Webcam]
    @State private var selectedWebcam: Webcam?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "video.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Webcams")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(webcams.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            if webcams.isEmpty {
                Text("Aucune webcam à proximité")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(webcams.prefix(5)) { webcam in
                            WebcamThumbnail(webcam: webcam)
                                .onTapGesture {
                                    HapticManager.shared.openSheet()
                                    selectedWebcam = webcam
                                    Analytics.webcamViewed(id: webcam.id)
                                }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .modifier(LiquidGlassRoundedModifier(cornerRadius: 14))
        .fullScreenCover(item: $selectedWebcam) { webcam in
            WebcamFullScreenView(webcam: webcam)
        }
    }
}

// MARK: - YouTube Player View (YouTube IFrame Player API)

private struct YouTubePlayerView: UIViewRepresentable {
    let embedUrl: String
    var onError: (() -> Void)? = nil

    /// Extract video ID from embed URL
    private var videoId: String {
        if let range = embedUrl.range(of: "/embed/") {
            let afterEmbed = String(embedUrl[range.upperBound...])
            return afterEmbed.components(separatedBy: "?").first ?? afterEmbed
        }
        if let range = embedUrl.range(of: "/live/") {
            let afterLive = String(embedUrl[range.upperBound...])
            return afterLive.components(separatedBy: "?").first ?? afterLive
        }
        if embedUrl.contains("youtu.be/") {
            return embedUrl.components(separatedBy: "youtu.be/").last?.components(separatedBy: "?").first ?? embedUrl
        }
        if let components = URLComponents(string: embedUrl),
           let vid = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return vid
        }
        return embedUrl
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Add script message handler for error detection
        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "youtubeError")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        // Store reference for fallback loading
        context.coordinator.webView = webView
        context.coordinator.videoId = videoId
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Simple iframe embed (most compatible) + postMessage error detection
        let origin = "https://anemouest.fr"
        let html = """
        <!DOCTYPE html>
        <html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>
        *{margin:0;padding:0;overflow:hidden;background:#000}
        iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:none}
        </style>
        </head><body>
        <iframe
          src="https://www.youtube.com/embed/\(videoId)?autoplay=1&playsinline=1&mute=1&controls=0&rel=0&modestbranding=1&enablejsapi=1&origin=\(origin)"
          allow="accelerometer;autoplay;clipboard-write;encrypted-media;gyroscope;picture-in-picture;web-share"
          referrerpolicy="strict-origin-when-cross-origin"
          allowfullscreen>
        </iframe>
        <script>
        window.addEventListener('message',function(e){
          try{
            var d=JSON.parse(e.data);
            if(d.event==='onError'){
              window.webkit.messageHandlers.youtubeError.postMessage({code:d.info||150});
            }
          }catch(ex){}
        });
        </script>
        </body></html>
        """

        if webView.url == nil {
            webView.loadHTMLString(html, baseURL: URL(string: origin))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onError: (() -> Void)?
        weak var webView: WKWebView?
        var videoId: String = ""
        private var triedDirectPage = false

        init(onError: (() -> Void)?) {
            self.onError = onError
        }

        /// Fallback: load YouTube mobile page directly (bypasses embed restrictions)
        private func loadDirectPage() {
            guard !triedDirectPage, let webView = webView else {
                onError?()
                return
            }
            triedDirectPage = true
            Log.debug("YouTube embed blocked, loading direct page for \(videoId)")

            // Enable scrolling for the full YouTube page
            webView.scrollView.isScrollEnabled = true

            if let url = URL(string: "https://m.youtube.com/watch?v=\(videoId)") {
                webView.load(URLRequest(url: url))
            } else {
                onError?()
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }

            if let action = body["action"] as? String, action == "openExternal",
               let urlString = body["url"] as? String,
               let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            } else if let code = body["code"] as? Int {
                Log.warning("YouTube embed error code: \(code)")
                // Error 150/152 = embed restricted → try direct page
                loadDirectPage()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Log.error("YouTube webview failed: \(error.localizedDescription)")
            if triedDirectPage {
                onError?()
            } else {
                loadDirectPage()
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Log.error("YouTube webview provisional navigation failed: \(error.localizedDescription)")
            if triedDirectPage {
                onError?()
            } else {
                loadDirectPage()
            }
        }
    }
}

// MARK: - Webcam Timeline Player

private struct WebcamTimelinePlayer: View {
    let timeline: [WebcamService.TimelineEntry]
    @Binding var selectedIndex: Int
    let isLoading: Bool
    let onSelectEntry: (WebcamService.TimelineEntry?) -> Void

    // Playback state
    @State private var isPlaying = false
    @State private var playbackSpeed: Double = 2.0 // frames per second
    private let playTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private let speeds: [Double] = [0.5, 1, 2, 4]

    // Calculate progress (0 = live, 1 = oldest)
    private var progress: Double {
        guard !timeline.isEmpty else { return 0 }
        if selectedIndex < 0 { return 0 }
        return Double(selectedIndex) / Double(timeline.count - 1)
    }

    // Time range
    private var oldestTime: Date? {
        timeline.last?.date
    }

    private var newestTime: Date? {
        timeline.first?.date
    }

    // Selected time label
    private var selectedTimeLabel: String {
        if selectedIndex < 0 { return "En direct" }
        guard selectedIndex < timeline.count else { return "" }

        let date = timeline[selectedIndex].date
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")

        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return "Hier " + formatter.string(from: date)
        } else {
            formatter.dateFormat = "E HH:mm"
            return formatter.string(from: date)
        }
    }

    // Relative time label
    private var relativeTimeLabel: String {
        if selectedIndex < 0 { return "" }
        guard selectedIndex < timeline.count else { return "" }

        let date = timeline[selectedIndex].date
        let hoursAgo = -date.timeIntervalSinceNow / 3600

        if hoursAgo < 1 {
            return "Il y a \(Int(hoursAgo * 60)) min"
        } else if hoursAgo < 24 {
            return "Il y a \(Int(hoursAgo))h"
        } else {
            let days = Int(hoursAgo / 24)
            return "Il y a \(days)j"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Time display + navigation + play
            HStack {
                // Left arrow = go towards Live (newer, lower index)
                Button {
                    stopPlayback()
                    navigateNewer()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.15), in: Circle())
                }
                .disabled(selectedIndex < 0)
                .opacity(selectedIndex < 0 ? 0.3 : 1)

                // Play/Pause button
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(isPlaying ? .orange.opacity(0.4) : .white.opacity(0.15), in: Circle())
                }

                Spacer()

                // Time display
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        if selectedIndex < 0 && !isPlaying {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                        }
                        if isPlaying {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                        Text(selectedTimeLabel)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }

                    if selectedIndex >= 0 {
                        Text(relativeTimeLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                // Speed selector (visible when playing or in history)
                if isPlaying {
                    Button {
                        cycleSpeed()
                    } label: {
                        Text(speedLabel)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .frame(width: 36, height: 36)
                            .background(.orange.opacity(0.2), in: Circle())
                    }
                } else {
                    // Right arrow = go towards Past (older, higher index)
                    Button {
                        stopPlayback()
                        navigateOlder()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                    .disabled(selectedIndex >= timeline.count - 1)
                    .opacity(selectedIndex >= timeline.count - 1 ? 0.3 : 1)
                }
            }
            .foregroundStyle(.white)

            // Scrubber bar
            GeometryReader { geo in
                let barWidth = geo.size.width
                let thumbPosition = selectedIndex < 0 ? 0 : (barWidth * progress)

                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(height: 6)

                    // Filled portion (from live to current)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.green, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, thumbPosition + 12), height: 6)

                    // Hour markers
                    ForEach(hourMarkers(width: barWidth), id: \.offset) { marker in
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(.white.opacity(0.4))
                                .frame(width: 1, height: 10)
                            Text(marker.label)
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .offset(x: marker.offset - 0.5)
                    }

                    // Thumb
                    Circle()
                        .fill(isPlaying ? .orange : (selectedIndex < 0 ? .green : .orange))
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .offset(x: thumbPosition - 9)
                        .animation(isPlaying ? .easeInOut(duration: 0.3) : nil, value: thumbPosition)
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            stopPlayback()
                            let x = value.location.x
                            let newProgress = max(0, min(1, x / barWidth))
                            let newIndex = newProgress < 0.02 ? -1 : Int(round(newProgress * Double(timeline.count - 1)))

                            if newIndex != selectedIndex {
                                HapticManager.shared.sliderTick()
                                selectedIndex = newIndex
                            }
                        }
                        .onEnded { _ in
                            HapticManager.shared.light()
                            if selectedIndex < 0 {
                                onSelectEntry(nil)
                            } else if selectedIndex < timeline.count {
                                onSelectEntry(timeline[selectedIndex])
                            }
                        }
                )
            }
            .frame(height: 30)

            // Quick jump buttons
            HStack(spacing: 8) {
                QuickJumpButton(label: "Live", isActive: selectedIndex < 0 && !isPlaying) {
                    stopPlayback()
                    selectedIndex = -1
                    onSelectEntry(nil)
                }

                QuickJumpButton(label: "-1h", isActive: false) {
                    stopPlayback()
                    jumpToHoursAgo(1)
                }

                QuickJumpButton(label: "-6h", isActive: false) {
                    stopPlayback()
                    jumpToHoursAgo(6)
                }

                QuickJumpButton(label: "-24h", isActive: false) {
                    stopPlayback()
                    jumpToHoursAgo(24)
                }

                QuickJumpButton(label: "-48h", isActive: selectedIndex == timeline.count - 1) {
                    stopPlayback()
                    if !timeline.isEmpty {
                        selectedIndex = timeline.count - 1
                        onSelectEntry(timeline.last)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .onReceive(playTimer) { _ in
            guard isPlaying else { return }
            advancePlayback()
        }
    }

    // MARK: - Playback

    private var speedLabel: String {
        if playbackSpeed < 1 {
            return String(format: "%.1f", playbackSpeed)
        }
        return "\(Int(playbackSpeed))x"
    }

    @State private var lastAdvanceTime: Date = .distantPast

    private func togglePlayback() {
        HapticManager.shared.medium()
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        // If at live or at oldest, start from live (index 0 = newest)
        if selectedIndex < 0 {
            selectedIndex = 0
            if let entry = timeline.first {
                onSelectEntry(entry)
            }
        } else if selectedIndex >= timeline.count - 1 {
            // Already at oldest, restart from newest
            selectedIndex = 0
            if let entry = timeline.first {
                onSelectEntry(entry)
            }
        }
        lastAdvanceTime = Date()
        isPlaying = true
    }

    private func stopPlayback() {
        isPlaying = false
    }

    private func advancePlayback() {
        // Don't advance if the current image is still loading
        guard !isLoading else { return }
        let interval = 1.0 / playbackSpeed
        guard Date().timeIntervalSince(lastAdvanceTime) >= interval else { return }
        lastAdvanceTime = Date()

        // Advance towards older (higher index), scrubber moves left → right
        let newIndex = selectedIndex + 1
        if newIndex >= timeline.count {
            // Reached oldest - stop
            selectedIndex = timeline.count - 1
            stopPlayback()
            HapticManager.shared.medium()
        } else {
            selectedIndex = newIndex
            onSelectEntry(timeline[newIndex])
        }
    }

    private func cycleSpeed() {
        HapticManager.shared.selection()
        if let currentIdx = speeds.firstIndex(of: playbackSpeed) {
            let nextIdx = (currentIdx + 1) % speeds.count
            playbackSpeed = speeds[nextIdx]
        } else {
            playbackSpeed = 2.0
        }
    }

    private func hourMarkers(width: CGFloat) -> [(offset: CGFloat, label: String)] {
        guard !timeline.isEmpty, let oldest = oldestTime else { return [] }

        var markers: [(offset: CGFloat, label: String)] = []
        let totalHours = -oldest.timeIntervalSinceNow / 3600
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH'h'"

        // Add markers every 6 hours
        for hours in stride(from: 6, through: Int(totalHours), by: 6) {
            let progress = Double(hours) / totalHours
            let offset = width * progress

            // Find the date for this hour
            let date = Date(timeIntervalSinceNow: -Double(hours) * 3600)
            let label = formatter.string(from: date)

            markers.append((offset: offset, label: label))
        }

        return markers
    }

    private func jumpToHoursAgo(_ hours: Int) {
        let targetTime = Date(timeIntervalSinceNow: -Double(hours) * 3600)

        // Find closest entry
        var closestIndex = 0
        var closestDiff = Double.infinity

        for (index, entry) in timeline.enumerated() {
            let diff = abs(entry.date.timeIntervalSince(targetTime))
            if diff < closestDiff {
                closestDiff = diff
                closestIndex = index
            }
        }

        HapticManager.shared.medium()
        selectedIndex = closestIndex
        if closestIndex < timeline.count {
            onSelectEntry(timeline[closestIndex])
        }
    }

    private func navigateOlder() {
        // Go back in time (older = higher index in timeline array)
        guard selectedIndex < timeline.count - 1 else { return }
        HapticManager.shared.selection()
        let newIndex = selectedIndex < 0 ? 0 : selectedIndex + 1
        selectedIndex = newIndex
        if newIndex < timeline.count {
            onSelectEntry(timeline[newIndex])
        }
    }

    private func navigateNewer() {
        // Go forward in time (newer = lower index, or live at -1)
        guard selectedIndex >= 0 else { return }
        HapticManager.shared.selection()
        let newIndex = selectedIndex - 1
        selectedIndex = newIndex
        if newIndex < 0 {
            onSelectEntry(nil)
        } else if newIndex < timeline.count {
            onSelectEntry(timeline[newIndex])
        }
    }
}

// MARK: - Quick Jump Button

private struct QuickJumpButton: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            action()
        }) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? .black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isActive ? .white : .white.opacity(0.15), in: Capsule())
        }
    }
}

// MARK: - Zoomable Image View (pinch-to-zoom, double-tap, pan)

private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let isPanoramic: Bool

    init(image: UIImage, isPanoramic: Bool = false) {
        self.image = image
        self.isPanoramic = isPanoramic
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ZoomableScrollView {
        let scrollView = ZoomableScrollView(isPanoramic: isPanoramic)
        scrollView.zoomDelegate = context.coordinator
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomableScrollView, context: Context) {
        scrollView.display(image: image)
    }

    class Coordinator: NSObject, ZoomableScrollViewDelegate {
        weak var scrollView: ZoomableScrollView?

        func zoomableScrollViewDidZoom(_ scrollView: ZoomableScrollView) {
            scrollView.centerImage()
        }
    }
}

// Protocol for zoom callbacks
private protocol ZoomableScrollViewDelegate: AnyObject {
    func zoomableScrollViewDidZoom(_ scrollView: ZoomableScrollView)
}

// Custom UIScrollView with zoom support
private class ZoomableScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    weak var zoomDelegate: ZoomableScrollViewDelegate?
    private var currentImage: UIImage?
    private var needsInitialSetup = true
    private let isPanoramic: Bool

    init(isPanoramic: Bool) {
        self.isPanoramic = isPanoramic
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        self.isPanoramic = false
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // ScrollView config
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bounces = true
        bouncesZoom = true
        backgroundColor = .clear
        decelerationRate = .normal
        minimumZoomScale = 1.0
        maximumZoomScale = 5.0
        contentInsetAdjustmentBehavior = .never

        // ImageView config
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)

        // Double-tap gesture
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.1 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let location = gesture.location(in: imageView)
            let rect = zoomRect(for: 2.5, center: location)
            zoom(to: rect, animated: true)
        }
    }

    private func zoomRect(for scale: CGFloat, center: CGPoint) -> CGRect {
        let width = bounds.width / scale
        let height = bounds.height / scale
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }

    func display(image: UIImage) {
        let imageChanged = currentImage !== image
        currentImage = image
        imageView.image = image

        if imageChanged {
            needsInitialSetup = true
            zoomScale = 1.0
        }

        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let image = currentImage, bounds.size != .zero else { return }

        let imageSize = image.size
        let boundsSize = bounds.size

        // Calculate the size that fits the image in the view
        let widthRatio = boundsSize.width / imageSize.width
        let heightRatio = boundsSize.height / imageSize.height

        let fitScale: CGFloat
        if isPanoramic {
            // Panoramic: use 60% of height
            fitScale = (boundsSize.height * 0.6) / imageSize.height
        } else {
            // Regular: fit entirely in view
            fitScale = min(widthRatio, heightRatio)
        }

        let scaledWidth = imageSize.width * fitScale
        let scaledHeight = imageSize.height * fitScale

        // Only update frame if not currently zooming
        if zoomScale == minimumZoomScale || needsInitialSetup {
            imageView.frame = CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight)
            contentSize = CGSize(width: max(scaledWidth, boundsSize.width), height: max(scaledHeight, boundsSize.height))
        }

        // Initial setup
        if needsInitialSetup {
            needsInitialSetup = false

            if isPanoramic && scaledWidth > boundsSize.width {
                // Center panoramic horizontally
                let offsetX = (scaledWidth - boundsSize.width) / 2
                contentOffset = CGPoint(x: offsetX, y: 0)
            } else {
                contentOffset = .zero
            }
        }

        // Always center the image when at minimum zoom
        if zoomScale <= minimumZoomScale + 0.01 {
            centerImage()
        }
    }

    func centerImage() {
        let boundsSize = bounds.size
        var frameToCenter = imageView.frame

        // Horizontal centering
        if frameToCenter.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }

        // Vertical centering
        if frameToCenter.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }

        imageView.frame = frameToCenter
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        zoomDelegate?.zoomableScrollViewDidZoom(self)
    }
}

// MARK: - Panoramic Image View (legacy alias for backward compatibility)

private struct PanoramicImageView: View {
    let image: UIImage

    var body: some View {
        ZoomableImageView(image: image, isPanoramic: true)
    }
}

// MARK: - Webcam Thumbnail

private struct WebcamThumbnail: View {
    let webcam: Webcam
    @State private var imageData: Data?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.systemGray5))

                if isLoading {
                    // Shimmer placeholder for thumbnails
                    ShimmerView()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if let data = imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "video.slash")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(webcam.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 80)
        }
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        // Use server-side thumbnail (400px, quality 50) for faster loading
        let storageUrl = WebcamService.shared.thumbnailImageUrl(for: webcam)

        if let data = await WebcamImageCache.shared.loadThumbnail(from: storageUrl) {
            await MainActor.run {
                self.imageData = data
                self.isLoading = false
            }
        } else {
            let fallbackUrl = WebcamService.shared.fallbackImageUrl(for: webcam)
            if let data = await WebcamImageCache.shared.loadThumbnail(from: fallbackUrl) {
                await MainActor.run {
                    self.imageData = data
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}
