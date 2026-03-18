import SwiftUI
import MapKit

// MARK: - Grid Filter Protocol

protocol HasCoordinate {
    var spotLatitude: Double { get }
    var spotLongitude: Double { get }
}

extension KiteSpot: HasCoordinate {
    var spotLatitude: Double { latitude }
    var spotLongitude: Double { longitude }
}

extension SurfSpot: HasCoordinate {
    var spotLatitude: Double { latitude }
    var spotLongitude: Double { longitude }
}

extension ParaglidingSpot: HasCoordinate {
    var spotLatitude: Double { latitude }
    var spotLongitude: Double { longitude }
}

extension Webcam: HasCoordinate {
    var spotLatitude: Double { latitude }
    var spotLongitude: Double { longitude }
}

// MARK: - Annotation Models

final class WindStationAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    var wind: Double
    var gust: Double
    var dirDeg: Double
    var isOnline: Bool
    var lastUpdate: Date?
    let stationId: String
    let source: WindSource
    var isSelected: Bool = false
    var zoomSpan: Double = 1.0
    var nearbyKiteColor: UIColor?
    var nearbySurfColor: UIColor?
    var nearbyParaglidingColor: UIColor?

    var hasNearbySpots: Bool {
        nearbyKiteColor != nil || nearbySurfColor != nil || nearbyParaglidingColor != nil
    }

    init(station: WindStation) {
        self.coordinate = station.coordinate
        self.wind = station.wind
        self.gust = station.gust
        self.dirDeg = station.direction
        self.isOnline = station.isOnline
        self.lastUpdate = station.lastUpdate
        self.stationId = station.stableId
        self.source = station.source
        super.init()
    }

    func update(from station: WindStation) {
        self.wind = station.wind
        self.gust = station.gust
        self.dirDeg = station.direction
        self.isOnline = station.isOnline
        self.lastUpdate = station.lastUpdate
    }

    /// Recalculate online status based on last update time (30 min threshold)
    var isEffectivelyOnline: Bool {
        guard isOnline else { return false }
        guard let update = lastUpdate else { return isOnline }
        return Date().timeIntervalSince(update) < 1800
    }

    var title: String? { nil }
}

final class KiteSpotAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let spotId: String
    let name: String
    let orientation: String
    let level: SpotLevel
    let spotType: SpotType
    var score: Int? // Praticability score (0-100)

    init(spot: KiteSpot) {
        self.coordinate = spot.coordinate
        self.spotId = spot.id
        self.name = spot.name
        self.orientation = spot.orientation
        self.level = spot.level
        self.spotType = spot.type
        super.init()
    }

    var title: String? { name }
}

final class SurfSpotAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let spotId: String
    let name: String
    let level: SurfLevel
    let waveType: SurfWaveType
    let orientation: String
    var score: Int? // Praticability score (0-100)

    init(spot: SurfSpot) {
        self.coordinate = spot.coordinate
        self.spotId = spot.id
        self.name = spot.name
        self.level = spot.level
        self.waveType = spot.waveType
        self.orientation = spot.orientation
        super.init()
    }

    var title: String? { name }
}

final class ParaglidingSpotAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let spotId: String
    let name: String
    let spotType: ParaglidingSpotType
    let level: ParaglidingLevel?
    var score: Int?

    init(spot: ParaglidingSpot) {
        self.coordinate = spot.coordinate
        self.spotId = spot.id
        self.name = spot.name
        self.spotType = spot.type
        self.level = spot.level
        super.init()
    }

    var title: String? { name }
}

final class WebcamAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let webcamId: String
    let name: String
    let location: String
    let thumbnailUrl: String  // Use thumbnail URL for cache consistency
    let refreshInterval: Int

    init(webcam: Webcam) {
        self.coordinate = webcam.coordinate
        self.webcamId = webcam.id
        self.name = webcam.name
        self.location = webcam.location
        // Store thumbnail URL directly for cache hit with prefetch
        self.thumbnailUrl = WebcamService.shared.thumbnailImageUrl(for: webcam)
        self.refreshInterval = webcam.refreshInterval
        super.init()
    }

    var title: String? { name }
}

final class WaveBuoyAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let buoyId: String
    let name: String
    var hm0: Double?            // Wave height in meters
    var tp: Double?             // Period in seconds
    var direction: Double?      // Wave direction
    var isOnline: Bool

    init(buoy: WaveBuoy) {
        self.coordinate = buoy.coordinate
        self.buoyId = buoy.id
        self.name = buoy.name
        self.hm0 = buoy.hm0
        self.tp = buoy.tp
        self.direction = buoy.direction
        self.isOnline = buoy.status.isOnline
        super.init()
    }

    func update(from buoy: WaveBuoy) {
        self.hm0 = buoy.hm0
        self.tp = buoy.tp
        self.direction = buoy.direction
        self.isOnline = buoy.status.isOnline
    }

    var title: String? { name }

    /// Color based on wave height
    var waveColor: UIColor {
        guard let hm0 = hm0 else { return .gray }
        switch hm0 {
        case ..<0.5:
            return UIColor(red: 0.70, green: 0.93, blue: 1.00, alpha: 1)
        case ..<1.0:
            return UIColor(red: 0.33, green: 0.85, blue: 0.92, alpha: 1)
        case ..<1.5:
            return UIColor(red: 0.35, green: 0.89, blue: 0.52, alpha: 1)
        case ..<2.0:
            return UIColor(red: 0.97, green: 0.90, blue: 0.33, alpha: 1)
        case ..<2.5:
            return UIColor(red: 0.98, green: 0.67, blue: 0.23, alpha: 1)
        case ..<3.0:
            return UIColor(red: 0.95, green: 0.22, blue: 0.26, alpha: 1)
        case ..<4.0:
            return UIColor(red: 0.83, green: 0.20, blue: 0.67, alpha: 1)
        default:
            return UIColor(red: 0.55, green: 0.24, blue: 0.78, alpha: 1)
        }
    }
}

// MARK: - Wind Color Scale (matching SwiftUI version)

private func windScaleColor(_ kts: Double) -> UIColor {
    switch kts {
    case ..<7:
        return UIColor(red: 0.70, green: 0.93, blue: 1.00, alpha: 1)
    case ..<11:
        return UIColor(red: 0.33, green: 0.85, blue: 0.92, alpha: 1)
    case ..<17:
        return UIColor(red: 0.35, green: 0.89, blue: 0.52, alpha: 1)
    case ..<22:
        return UIColor(red: 0.97, green: 0.90, blue: 0.33, alpha: 1)
    case ..<28:
        return UIColor(red: 0.98, green: 0.67, blue: 0.23, alpha: 1)
    case ..<34:
        return UIColor(red: 0.95, green: 0.22, blue: 0.26, alpha: 1)
    case ..<41:
        return UIColor(red: 0.83, green: 0.20, blue: 0.67, alpha: 1)
    case ..<48:
        return UIColor(red: 0.55, green: 0.24, blue: 0.78, alpha: 1)
    default:
        return UIColor(red: 0.39, green: 0.24, blue: 0.63, alpha: 1)
    }
}

// MARK: - Optimized Map View

struct OptimizedMapView: UIViewRepresentable {
    @Binding var camera: MapCameraPosition
    let selectedStationId: String?
    let windStations: [WindStation]
    let kiteSpots: [KiteSpot]
    let surfSpots: [SurfSpot]
    let showKiteSpots: Bool  // Whether to show individual kite spot annotations
    let showSurfSpots: Bool  // Whether to show individual surf spot annotations
    let webcams: [Webcam]
    let waveBuoys: [WaveBuoy]
    let mapType: MKMapType
    let showSeaMap: Bool
    let isCenteringCamera: Bool  // Flag to prevent region conflicts during programmatic moves
    var showUserLocation: Bool = true
    let onTapStationById: (String) -> Void
    let onTapKiteSpot: (KiteSpot) -> Void
    let onTapSurfSpot: (SurfSpot) -> Void
    let paraglidingSpots: [ParaglidingSpot]
    let showParaglidingSpots: Bool
    let onTapParaglidingSpot: (ParaglidingSpot) -> Void
    let onTapWebcam: (Webcam) -> Void
    let onTapWaveBuoy: (WaveBuoy) -> Void

    // Praticable spots
    var showPraticableSpots: Bool = false
    var spotScores: [String: Int] = [:]

    // OpenSeaMap tile overlay
    private static let seaMapOverlay: MKTileOverlay = {
        let overlay = MKTileOverlay(urlTemplate: "https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png")
        overlay.canReplaceMapContent = false
        overlay.maximumZ = 18
        overlay.minimumZ = 9
        return overlay
    }()

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = showUserLocation
        mapView.mapType = mapType

        // Performance optimizations
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.showsBuildings = false
        mapView.showsTraffic = false
        mapView.pointOfInterestFilter = .excludingAll

        // Add OpenSeaMap overlay if enabled
        if showSeaMap {
            mapView.addOverlay(Self.seaMapOverlay, level: .aboveLabels)
        }

        // Register annotation views
        mapView.register(WindStationAnnotationView.self, forAnnotationViewWithReuseIdentifier: "windstation")
        mapView.register(KiteSpotAnnotationView.self, forAnnotationViewWithReuseIdentifier: "kitespot")
        mapView.register(SurfSpotAnnotationView.self, forAnnotationViewWithReuseIdentifier: "surfspot")
        mapView.register(WebcamAnnotationView.self, forAnnotationViewWithReuseIdentifier: "webcam")
        mapView.register(WaveBuoyAnnotationView.self, forAnnotationViewWithReuseIdentifier: "wavebuoy")
        mapView.register(ParaglidingSpotAnnotationView.self, forAnnotationViewWithReuseIdentifier: "paraglidingspot")
        mapView.register(ClusterAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        mapView.register(SurfSpotClusterAnnotationView.self, forAnnotationViewWithReuseIdentifier: "surfCluster")
        mapView.register(KiteSpotClusterAnnotationView.self, forAnnotationViewWithReuseIdentifier: "kiteCluster")
        mapView.register(ParaglidingSpotClusterAnnotationView.self, forAnnotationViewWithReuseIdentifier: "paraglidingCluster")

        // Fast tap gesture recognizer for immediate response
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.delaysTouchesBegan = false
        tapGesture.delaysTouchesEnded = false
        mapView.addGestureRecognizer(tapGesture)

        // Limit camera to France metropolitan + Corsica (with generous padding)
        let franceBounds = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 46.2, longitude: 2.5),
            span: MKCoordinateSpan(latitudeDelta: 14.0, longitudeDelta: 18.0)
        )
        mapView.cameraBoundary = MKMapView.CameraBoundary(coordinateRegion: franceBounds)
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(maxCenterCoordinateDistance: 2_500_000)

        // Set initial region
        if let region = camera.region {
            mapView.setRegion(region, animated: false)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        // Update map type if changed (always, even during interaction)
        if mapView.mapType != mapType {
            mapView.mapType = mapType
        }

        // Update user location visibility
        if mapView.showsUserLocation != showUserLocation {
            mapView.showsUserLocation = showUserLocation
        }

        // Update OpenSeaMap overlay - check for exact instance, not just any MKTileOverlay
        let hasSeaMapOverlay = mapView.overlays.contains { $0 === Self.seaMapOverlay }
        if showSeaMap && !hasSeaMapOverlay {
            mapView.addOverlay(Self.seaMapOverlay, level: .aboveLabels)
        } else if !showSeaMap && hasSeaMapOverlay {
            mapView.removeOverlay(Self.seaMapOverlay)
        }

        // Update region if changed externally (during programmatic centering)
        if let region = camera.region, isCenteringCamera {
            let currentCenter = mapView.region.center
            let newCenter = region.center
            let currentSpan = mapView.region.span
            let newSpan = region.span

            let centerDistance = abs(currentCenter.latitude - newCenter.latitude) + abs(currentCenter.longitude - newCenter.longitude)
            let spanDifference = abs(currentSpan.latitudeDelta - newSpan.latitudeDelta)

            // Update if center moved OR span changed significantly
            if centerDistance > 0.001 || spanDifference > 0.001 {
                mapView.setRegion(region, animated: true)
            }
        }

        // Detect score changes — these are lightweight updates that bypass throttle
        let scoresChanged = spotScores.count != context.coordinator.lastSpotScoresCount
        context.coordinator.lastSpotScoresCount = spotScores.count

        // Skip annotation updates during user interaction to avoid jank
        // (but allow score-only updates through)
        if context.coordinator.isUserInteracting && !scoresChanged {
            return
        }

        // Throttle annotation updates to avoid redundant work during rapid SwiftUI state changes
        // (but allow score-only updates through)
        let now = CACurrentMediaTime()
        if now - context.coordinator.lastAnnotationUpdate < context.coordinator.annotationUpdateInterval && !scoresChanged {
            return
        }
        context.coordinator.lastAnnotationUpdate = now

        // Batch annotation updates
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateAnnotations(mapView: mapView, context: context)
        CATransaction.commit()
    }

    private func updateAnnotations(mapView: MKMapView, context: Context) {
        // Single-pass categorization of all existing annotations
        var existingStations: [WindStationAnnotation] = []
        var existingKiteSpots: [KiteSpotAnnotation] = []
        var existingSurfSpots: [SurfSpotAnnotation] = []
        var existingParaglidingSpots: [ParaglidingSpotAnnotation] = []
        var existingWebcams: [WebcamAnnotation] = []
        var existingWaveBuoys: [WaveBuoyAnnotation] = []

        for annotation in mapView.annotations {
            if let s = annotation as? WindStationAnnotation { existingStations.append(s) }
            else if let s = annotation as? KiteSpotAnnotation { existingKiteSpots.append(s) }
            else if let s = annotation as? SurfSpotAnnotation { existingSurfSpots.append(s) }
            else if let s = annotation as? ParaglidingSpotAnnotation { existingParaglidingSpots.append(s) }
            else if let s = annotation as? WebcamAnnotation { existingWebcams.append(s) }
            else if let s = annotation as? WaveBuoyAnnotation { existingWaveBuoys.append(s) }
        }

        // Get visible region with buffer for smooth panning
        let visibleRegion = mapView.region
        let buffer = 0.5 // Add 50% buffer around visible area
        let minLat = visibleRegion.center.latitude - visibleRegion.span.latitudeDelta * (0.5 + buffer)
        let maxLat = visibleRegion.center.latitude + visibleRegion.span.latitudeDelta * (0.5 + buffer)
        let minLon = visibleRegion.center.longitude - visibleRegion.span.longitudeDelta * (0.5 + buffer)
        let maxLon = visibleRegion.center.longitude + visibleRegion.span.longitudeDelta * (0.5 + buffer)

        // Zoom level from span
        let zoomSpan = visibleRegion.span.latitudeDelta

        // Filter stations by visible region with density limit
        let allVisibleStations = windStations.filter { station in
            let lat = station.coordinate.latitude
            let lon = station.coordinate.longitude
            return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
        }

        // Adaptive density: limit annotations based on zoom level
        let visibleStations: [WindStation]
        let maxStations = 150 // Max annotations for smooth rendering
        if allVisibleStations.count > maxStations {
            // Dynamic grid size based on visible area and target count
            let latRange = maxLat - minLat
            let lonRange = maxLon - minLon
            let cellsPerAxis = max(Int(sqrt(Double(maxStations))), 1)
            let gridLat = latRange / Double(cellsPerAxis)
            let gridLon = lonRange / Double(cellsPerAxis)
            visibleStations = filterStationsByGrid(allVisibleStations, gridSize: min(gridLat, gridLon), minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
        } else {
            visibleStations = allVisibleStations
        }

        // Handle wind stations
        let existingStationIds = Set(existingStations.map { $0.stationId })
        let visibleStationIds = Set(visibleStations.map { $0.stableId })

        // Remove stations outside visible region
        let stationsOutOfView = existingStations.filter { !visibleStationIds.contains($0.stationId) }
        if !stationsOutOfView.isEmpty {
            mapView.removeAnnotations(stationsOutOfView)
        }

        // Pre-compute nearby spot colors with caching
        // Only recalculate when spot data or visibility flags change
        let nearbyRadius = 0.03 // ~3km
        var spotsHash = 0
        spotsHash ^= kiteSpots.count &* 31
        spotsHash ^= surfSpots.count &* 97
        spotsHash ^= paraglidingSpots.count &* 127
        spotsHash ^= (showKiteSpots ? 1 : 0) &* 251
        spotsHash ^= (showSurfSpots ? 1 : 0) &* 509
        spotsHash ^= (showParaglidingSpots ? 1 : 0) &* 1021

        let needsNearbyRecalc = spotsHash != context.coordinator.lastSpotsHash
        if needsNearbyRecalc {
            context.coordinator.lastSpotsHash = spotsHash
            context.coordinator.cachedNearbyColors.removeAll(keepingCapacity: true)

            // Build cache for ALL stations (not just visible) — O(N×M) once
            for station in windStations {
                let coord = station.coordinate
                var kiteColor: UIColor? = nil
                var surfColor: UIColor? = nil
                var paraglidingColor: UIColor? = nil

                if showKiteSpots {
                    var bestDist = Double.greatestFiniteMagnitude
                    var bestLevel: SpotLevel?
                    for spot in kiteSpots {
                        let dLat = spot.latitude - coord.latitude
                        let dLon = spot.longitude - coord.longitude
                        guard abs(dLat) < nearbyRadius && abs(dLon) < nearbyRadius else { continue }
                        let dist = dLat * dLat + dLon * dLon
                        if dist < bestDist { bestDist = dist; bestLevel = spot.level }
                    }
                    if let level = bestLevel {
                        kiteColor = Self.kiteColorForLevel(level)
                    }
                }

                if showSurfSpots {
                    var bestDist = Double.greatestFiniteMagnitude
                    var bestLevel: SurfLevel?
                    for spot in surfSpots {
                        let dLat = spot.latitude - coord.latitude
                        let dLon = spot.longitude - coord.longitude
                        guard abs(dLat) < nearbyRadius && abs(dLon) < nearbyRadius else { continue }
                        let dist = dLat * dLat + dLon * dLon
                        if dist < bestDist { bestDist = dist; bestLevel = spot.level }
                    }
                    if let level = bestLevel {
                        surfColor = Self.surfColorForLevel(level)
                    }
                }

                if showParaglidingSpots {
                    var bestDist = Double.greatestFiniteMagnitude
                    var found = false
                    var bestLevel: ParaglidingLevel?
                    for spot in paraglidingSpots {
                        let dLat = spot.latitude - coord.latitude
                        let dLon = spot.longitude - coord.longitude
                        guard abs(dLat) < nearbyRadius && abs(dLon) < nearbyRadius else { continue }
                        let dist = dLat * dLat + dLon * dLon
                        if dist < bestDist { bestDist = dist; bestLevel = spot.level; found = true }
                    }
                    if found {
                        paraglidingColor = Self.paraglidingColorForLevel(bestLevel)
                    }
                }

                context.coordinator.cachedNearbyColors[station.stableId] = (kiteColor, surfColor, paraglidingColor)
            }
        }

        func applyNearbyColors(on ann: WindStationAnnotation) {
            if let cached = context.coordinator.cachedNearbyColors[ann.stationId] {
                ann.nearbyKiteColor = cached.kite
                ann.nearbySurfColor = cached.surf
                ann.nearbyParaglidingColor = cached.paragliding
            } else {
                ann.nearbyKiteColor = nil
                ann.nearbySurfColor = nil
                ann.nearbyParaglidingColor = nil
            }
        }

        // Add new station annotations
        for station in visibleStations {
            if !existingStationIds.contains(station.stableId) {
                let ann = WindStationAnnotation(station: station)
                ann.isSelected = station.stableId == selectedStationId
                ann.zoomSpan = zoomSpan
                applyNearbyColors(on: ann)
                mapView.addAnnotation(ann)
            }
        }

        // Update existing station annotations with new data (use pre-computed list minus removed)
        let stationDataById = Dictionary(uniqueKeysWithValues: visibleStations.map { ($0.stableId, $0) })
        let removedStationIds = Set(stationsOutOfView.map { $0.stationId })

        for existing in existingStations where !removedStationIds.contains(existing.stationId) {
            existing.isSelected = existing.stationId == selectedStationId
            if let stationData = stationDataById[existing.stationId] {
                existing.update(from: stationData)
            }
            existing.zoomSpan = zoomSpan
            applyNearbyColors(on: existing)
            if let view = mapView.view(for: existing) as? WindStationAnnotationView {
                view.configure(with: existing)
            }
        }

        // Update kite spot annotations (density-adaptive filtering)
        if showKiteSpots && zoomSpan < 4.0 {
            let visibleKiteSpots = filterByDensity(kiteSpots, minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, targetCount: 80)

            let visibleKiteIds = Set(visibleKiteSpots.map { $0.id })
            let existingKiteSpotIds = Set(existingKiteSpots.map { $0.spotId })

            let kiteSpotsToRemove = existingKiteSpots.filter { !visibleKiteIds.contains($0.spotId) }
            if !kiteSpotsToRemove.isEmpty {
                mapView.removeAnnotations(kiteSpotsToRemove)
            }

            for spot in visibleKiteSpots {
                if !existingKiteSpotIds.contains(spot.id) {
                    let annotation = KiteSpotAnnotation(spot: spot)
                    mapView.addAnnotation(annotation)
                }
            }
        } else {
            if !existingKiteSpots.isEmpty {
                mapView.removeAnnotations(existingKiteSpots)
            }
        }

        // Update surf spot annotations (density-adaptive filtering)
        if showSurfSpots && zoomSpan < 4.0 {
            let visibleSurfSpots = filterByDensity(surfSpots, minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, targetCount: 80)

            let visibleSurfIds = Set(visibleSurfSpots.map { $0.id })
            let existingSurfSpotIds = Set(existingSurfSpots.map { $0.spotId })

            let surfSpotsToRemove = existingSurfSpots.filter { !visibleSurfIds.contains($0.spotId) }
            if !surfSpotsToRemove.isEmpty {
                mapView.removeAnnotations(surfSpotsToRemove)
            }

            for spot in visibleSurfSpots {
                if !existingSurfSpotIds.contains(spot.id) {
                    let annotation = SurfSpotAnnotation(spot: spot)
                    mapView.addAnnotation(annotation)
                }
            }
        } else {
            if !existingSurfSpots.isEmpty {
                mapView.removeAnnotations(existingSurfSpots)
            }
        }

        // Update paragliding spot annotations (density-adaptive filtering)
        if showParaglidingSpots && zoomSpan < 4.0 {
            let visibleParaglidingSpots = filterByDensity(paraglidingSpots, minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, targetCount: 100)

            let visibleParaglidingIds = Set(visibleParaglidingSpots.map { $0.id })
            let existingParaglidingSpotIds = Set(existingParaglidingSpots.map { $0.spotId })

            let paraglidingSpotsToRemove = existingParaglidingSpots.filter { !visibleParaglidingIds.contains($0.spotId) }
            if !paraglidingSpotsToRemove.isEmpty {
                mapView.removeAnnotations(paraglidingSpotsToRemove)
            }

            for spot in visibleParaglidingSpots {
                if !existingParaglidingSpotIds.contains(spot.id) {
                    let annotation = ParaglidingSpotAnnotation(spot: spot)
                    mapView.addAnnotation(annotation)
                }
            }
        } else {
            if !existingParaglidingSpots.isEmpty {
                mapView.removeAnnotations(existingParaglidingSpots)
            }
        }

        // Update spot scores on existing annotations (score-only update, no icon rebuild)
        if showPraticableSpots && !spotScores.isEmpty {
            for annotation in mapView.annotations {
                if let kite = annotation as? KiteSpotAnnotation {
                    let newScore = spotScores[kite.spotId]
                    if kite.score != newScore {
                        kite.score = newScore
                        if let view = mapView.view(for: kite) as? KiteSpotAnnotationView {
                            if let s = newScore { view.showScore(s) } else { view.hideScore() }
                        }
                    }
                } else if let surf = annotation as? SurfSpotAnnotation {
                    let newScore = spotScores[surf.spotId]
                    if surf.score != newScore {
                        surf.score = newScore
                        if let view = mapView.view(for: surf) as? SurfSpotAnnotationView {
                            if let s = newScore { view.showScore(s) } else { view.hideScore() }
                        }
                    }
                } else if let para = annotation as? ParaglidingSpotAnnotation {
                    let newScore = spotScores[para.spotId]
                    if para.score != newScore {
                        para.score = newScore
                        if let view = mapView.view(for: para) as? ParaglidingSpotAnnotationView {
                            if let s = newScore { view.showScore(s) } else { view.hideScore() }
                        }
                    }
                }
            }
        } else if !showPraticableSpots {
            for annotation in mapView.annotations {
                if let kite = annotation as? KiteSpotAnnotation, kite.score != nil {
                    kite.score = nil
                    (mapView.view(for: kite) as? KiteSpotAnnotationView)?.hideScore()
                } else if let surf = annotation as? SurfSpotAnnotation, surf.score != nil {
                    surf.score = nil
                    (mapView.view(for: surf) as? SurfSpotAnnotationView)?.hideScore()
                } else if let para = annotation as? ParaglidingSpotAnnotation, para.score != nil {
                    para.score = nil
                    (mapView.view(for: para) as? ParaglidingSpotAnnotationView)?.hideScore()
                }
            }
        }

        // Update webcam annotations (density-adaptive filtering, hidden at very wide zoom)
        let visibleWebcams: [Webcam]
        if zoomSpan > 6.0 {
            visibleWebcams = []
        } else {
            visibleWebcams = filterByDensity(webcams, minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, targetCount: 50)
        }

        let visibleWebcamIds = Set(visibleWebcams.map { $0.id })
        let existingWebcamIds = Set(existingWebcams.map { $0.webcamId })

        // Remove webcams no longer visible at this zoom
        let webcamsToRemove = existingWebcams.filter { !visibleWebcamIds.contains($0.webcamId) }
        if !webcamsToRemove.isEmpty {
            mapView.removeAnnotations(webcamsToRemove)
        }

        // Add new visible webcams
        for webcam in visibleWebcams {
            if !existingWebcamIds.contains(webcam.id) {
                let annotation = WebcamAnnotation(webcam: webcam)
                mapView.addAnnotation(annotation)
            }
        }

        // Update wave buoy annotations
        let currentWaveBuoyIds = Set(waveBuoys.map { $0.id })
        let existingWaveBuoyIds = Set(existingWaveBuoys.map { $0.buoyId })

        // Remove wave buoys no longer in list
        let waveBuoysToRemove = existingWaveBuoys.filter { !currentWaveBuoyIds.contains($0.buoyId) }
        if !waveBuoysToRemove.isEmpty {
            mapView.removeAnnotations(waveBuoysToRemove)
        }

        // Add or update wave buoys
        for buoy in waveBuoys {
            if let existing = existingWaveBuoys.first(where: { $0.buoyId == buoy.id }) {
                // Update existing
                existing.update(from: buoy)
                if let view = mapView.view(for: existing) as? WaveBuoyAnnotationView {
                    view.configure(with: existing)
                }
            } else if !existingWaveBuoyIds.contains(buoy.id) {
                // Add new
                let annotation = WaveBuoyAnnotation(buoy: buoy)
                mapView.addAnnotation(annotation)
            }
        }
    }

    // MARK: - Spot level color helpers

    static func kiteColorForLevel(_ level: SpotLevel) -> UIColor {
        switch level {
        case .beginner: return UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1.0)
        case .intermediate: return UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1.0)
        case .advanced: return UIColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1.0)
        case .expert: return UIColor(red: 0.7, green: 0.4, blue: 0.9, alpha: 1.0)
        }
    }

    static func surfColorForLevel(_ level: SurfLevel) -> UIColor {
        switch level {
        case .beginner: return UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1.0)
        case .intermediate: return UIColor(red: 1.0, green: 0.8, blue: 0.3, alpha: 1.0)
        case .advanced: return UIColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 1.0)
        case .expert: return UIColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
        }
    }

    static func paraglidingColorForLevel(_ level: ParaglidingLevel?) -> UIColor {
        switch level {
        case .ippi3: return UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1.0)
        case .ippi4: return UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1.0)
        case .ippi5: return UIColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1.0)
        case .none: return UIColor.white
        }
    }

    // Filter wind stations by grid: keep 1 per grid cell, prefer online stations with recent data
    private func filterStationsByGrid(_ stations: [WindStation], gridSize: Double, minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) -> [WindStation] {
        var gridCells: [String: WindStation] = [:]
        for station in stations {
            let lat = station.coordinate.latitude
            let lon = station.coordinate.longitude
            guard lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon else { continue }

            let cellKey = "\(Int(lat / gridSize)),\(Int(lon / gridSize))"
            if let existing = gridCells[cellKey] {
                // Prefer online station, then higher wind (more useful data)
                if !existing.isOnline && station.isOnline {
                    gridCells[cellKey] = station
                } else if existing.isOnline == station.isOnline && station.wind > existing.wind {
                    gridCells[cellKey] = station
                }
            } else {
                gridCells[cellKey] = station
            }
        }
        return Array(gridCells.values)
    }

    /// Density-adaptive grid filter: keeps at most `targetCount` items in the visible region.
    /// Dynamically computes grid cell size based on visible area and target density.
    private func filterByDensity<T: HasCoordinate>(_ items: [T], minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, targetCount: Int = 80) -> [T] {
        // Filter to visible region
        let visible = items.filter { item in
            let lat = item.spotLatitude
            let lon = item.spotLongitude
            return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
        }
        if visible.count <= targetCount { return visible }

        // Compute grid size to produce ~targetCount cells
        let latRange = maxLat - minLat
        let lonRange = maxLon - minLon
        let cellsPerAxis = max(Int(sqrt(Double(targetCount))), 1)
        let gridLat = latRange / Double(cellsPerAxis)
        let gridLon = lonRange / Double(cellsPerAxis)
        guard gridLat > 0, gridLon > 0 else { return visible }

        var grid: [String: T] = [:]
        for item in visible {
            let key = "\(Int(item.spotLatitude / gridLat)),\(Int(item.spotLongitude / gridLon))"
            if grid[key] == nil { grid[key] = item }
        }
        return Array(grid.values)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: OptimizedMapView
        var isUserInteracting = false
        var lastAnnotationUpdate: CFTimeInterval = 0
        let annotationUpdateInterval: CFTimeInterval = 0.15
        var lastSpotScoresCount: Int = 0

        // Cache for nearby spot colors per station — avoids O(N×M) recalculation on every pan
        var cachedNearbyColors: [String: (kite: UIColor?, surf: UIColor?, paragliding: UIColor?)] = [:]
        var lastSpotsHash: Int = 0

        init(_ parent: OptimizedMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // Check if user is dragging (gesture-based change)
            if let gestureRecognizers = mapView.subviews.first?.gestureRecognizers {
                for recognizer in gestureRecognizers {
                    if recognizer.state == .began || recognizer.state == .changed {
                        isUserInteracting = true
                        break
                    }
                }
            }

        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Use default Apple location indicator
            if annotation is MKUserLocation { return nil }

            if let cluster = annotation as? MKClusterAnnotation {
                // Check if this is a kite spot cluster
                let isKiteCluster = cluster.memberAnnotations.first is KiteSpotAnnotation
                // Check if this is a surf spot cluster
                let isSurfCluster = cluster.memberAnnotations.first is SurfSpotAnnotation

                let isParaglidingCluster = cluster.memberAnnotations.first is ParaglidingSpotAnnotation

                if isParaglidingCluster {
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: "paraglidingCluster", for: annotation) as? ParaglidingSpotClusterAnnotationView
                        ?? ParaglidingSpotClusterAnnotationView(annotation: annotation, reuseIdentifier: "paraglidingCluster")
                    view.configure(with: cluster)
                    view.displayPriority = .defaultHigh
                    view.collisionMode = .circle
                    view.zPriority = .min
                    return view
                } else if isKiteCluster {
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: "kiteCluster", for: annotation) as? KiteSpotClusterAnnotationView
                        ?? KiteSpotClusterAnnotationView(annotation: annotation, reuseIdentifier: "kiteCluster")
                    view.configure(with: cluster)
                    view.displayPriority = .defaultHigh
                    view.collisionMode = .circle
                    view.zPriority = .min
                    return view
                } else if isSurfCluster {
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: "surfCluster", for: annotation) as? SurfSpotClusterAnnotationView
                        ?? SurfSpotClusterAnnotationView(annotation: annotation, reuseIdentifier: "surfCluster")
                    view.configure(with: cluster)
                    view.displayPriority = .defaultHigh
                    view.collisionMode = .circle
                    view.zPriority = .min
                    return view
                } else {
                    let view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: annotation) as? ClusterAnnotationView
                        ?? ClusterAnnotationView(annotation: annotation, reuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
                    view.configure(with: cluster)
                    view.displayPriority = .required
                    view.collisionMode = .circle
                    return view
                }
            }

            if let station = annotation as? WindStationAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "windstation", for: annotation) as? WindStationAnnotationView
                    ?? WindStationAnnotationView(annotation: annotation, reuseIdentifier: "windstation")
                view.configure(with: station)
                view.clusteringIdentifier = "cluster"
                view.displayPriority = .required
                view.zPriority = .max
                view.collisionMode = .circle
                return view
            }

            if let kiteSpot = annotation as? KiteSpotAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "kitespot", for: annotation) as? KiteSpotAnnotationView
                    ?? KiteSpotAnnotationView(annotation: annotation, reuseIdentifier: "kitespot")
                view.configure(with: kiteSpot)
                view.clusteringIdentifier = "kiteCluster"
                view.displayPriority = .defaultHigh
                view.zPriority = .min
                view.collisionMode = .circle
                return view
            }

            if let surfSpot = annotation as? SurfSpotAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "surfspot", for: annotation) as? SurfSpotAnnotationView
                    ?? SurfSpotAnnotationView(annotation: annotation, reuseIdentifier: "surfspot")
                view.configure(with: surfSpot)
                view.clusteringIdentifier = "surfCluster"
                view.displayPriority = .defaultHigh
                view.zPriority = .min
                view.collisionMode = .circle
                return view
            }

            if let paraglidingSpot = annotation as? ParaglidingSpotAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "paraglidingspot", for: annotation) as? ParaglidingSpotAnnotationView
                    ?? ParaglidingSpotAnnotationView(annotation: annotation, reuseIdentifier: "paraglidingspot")
                view.configure(with: paraglidingSpot)
                view.clusteringIdentifier = "paraglidingCluster"
                view.displayPriority = .defaultHigh
                view.zPriority = .min
                view.collisionMode = .circle
                return view
            }

            if let webcam = annotation as? WebcamAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "webcam", for: annotation) as? WebcamAnnotationView
                    ?? WebcamAnnotationView(annotation: annotation, reuseIdentifier: "webcam")
                let shouldAnimate = view.configure(with: webcam)
                // No clustering - let nearby webcams overlap to show there are multiple
                view.clusteringIdentifier = nil
                view.displayPriority = .required
                view.collisionMode = .none  // Allow overlap instead of hiding
                view.zPriority = .min

                // Animate appearance when showing a new webcam
                if shouldAnimate {
                    view.animateAppearance()
                }
                return view
            }

            if let waveBuoy = annotation as? WaveBuoyAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "wavebuoy", for: annotation) as? WaveBuoyAnnotationView
                    ?? WaveBuoyAnnotationView(annotation: annotation, reuseIdentifier: "wavebuoy")
                view.configure(with: waveBuoy)
                // Never cluster wave buoys - always show them
                view.clusteringIdentifier = nil
                view.displayPriority = .defaultLow
                view.zPriority = .min  // Behind wind stations
                view.collisionMode = .none
                return view
            }

            return nil
        }

        // Fast tap handler using gesture recognizer
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)

            // First pass: clusters (zoom in to split)
            for annotation in mapView.annotations where annotation is MKClusterAnnotation {
                guard let view = mapView.view(for: annotation), !view.isHidden else { continue }
                let hitArea = view.frame.insetBy(dx: -15, dy: -15)
                if hitArea.contains(point) {
                    handleAnnotationTap(annotation, mapView: mapView)
                    return
                }
            }

            // Second pass: individual annotations (only visible ones, not clustered)
            for annotation in mapView.annotations where !(annotation is MKClusterAnnotation) && !(annotation is MKUserLocation) {
                guard let view = mapView.view(for: annotation), !view.isHidden else { continue }
                let hitArea = view.frame.insetBy(dx: -15, dy: -15)
                if hitArea.contains(point) {
                    handleAnnotationTap(annotation, mapView: mapView)
                    return
                }
            }
        }

        private func handleAnnotationTap(_ annotation: MKAnnotation, mapView: MKMapView) {
            // Handle cluster tap - always zoom IN
            if let cluster = annotation as? MKClusterAnnotation {
                let currentSpan = mapView.region.span
                let clusterCoord = cluster.coordinate

                // Zoom in by 50% centered on the cluster
                let newSpan = MKCoordinateSpan(
                    latitudeDelta: currentSpan.latitudeDelta * 0.5,
                    longitudeDelta: currentSpan.longitudeDelta * 0.5
                )

                let region = MKCoordinateRegion(center: clusterCoord, span: newSpan)
                mapView.setRegion(region, animated: true)
                return
            }

            // Handle station tap
            if let station = annotation as? WindStationAnnotation {
                parent.onTapStationById(station.stationId)
                return
            }

            // Handle kite spot tap
            if let kiteSpot = annotation as? KiteSpotAnnotation {
                if let spot = parent.kiteSpots.first(where: { $0.id == kiteSpot.spotId }) {
                    parent.onTapKiteSpot(spot)
                }
                return
            }

            // Handle surf spot tap
            if let surfSpot = annotation as? SurfSpotAnnotation {
                if let spot = parent.surfSpots.first(where: { $0.id == surfSpot.spotId }) {
                    parent.onTapSurfSpot(spot)
                }
                return
            }

            // Handle paragliding spot tap
            if let paraglidingSpot = annotation as? ParaglidingSpotAnnotation {
                if let spot = parent.paraglidingSpots.first(where: { $0.id == paraglidingSpot.spotId }) {
                    parent.onTapParaglidingSpot(spot)
                }
                return
            }

            // Handle webcam tap
            if let webcamAnnotation = annotation as? WebcamAnnotation {
                if let webcam = parent.webcams.first(where: { $0.id == webcamAnnotation.webcamId }) {
                    parent.onTapWebcam(webcam)
                }
                return
            }

            // Handle wave buoy tap
            if let waveBuoyAnnotation = annotation as? WaveBuoyAnnotation {
                if let buoy = parent.waveBuoys.first(where: { $0.id == waveBuoyAnnotation.buoyId }) {
                    parent.onTapWaveBuoy(buoy)
                }
            }
        }

        // Disable default selection behavior (we use gesture instead)
        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            isUserInteracting = false

            let region = mapView.region

            // MKTileOverlayRenderer handles its own redraw on region change

            // Sync camera back to SwiftUI only if region moved significantly
            // Avoids feedback loop: regionDidChange → camera update → SwiftUI → updateUIView → updateAnnotations
            if !parent.isCenteringCamera {
                let cur = parent.camera.region
                let moved = cur == nil ||
                    abs(cur!.center.latitude - region.center.latitude) > 0.0005 ||
                    abs(cur!.center.longitude - region.center.longitude) > 0.0005 ||
                    abs(cur!.span.latitudeDelta - region.span.latitudeDelta) > 0.001
                if moved {
                    DispatchQueue.main.async {
                        self.parent.camera = .region(region)
                    }
                }
            }

            // Note: annotations are updated by updateUIView (triggered by camera sync above)
            // No need for a separate refreshVisibleAnnotations call

            // Update viewport bbox on WindStationManager (for server-side filtering)
            let buffer = 0.3 // 30% buffer for smoother panning
            let bbox = WindStationManager.MapBBox(
                latSW: region.center.latitude - region.span.latitudeDelta * (0.5 + buffer),
                lonSW: region.center.longitude - region.span.longitudeDelta * (0.5 + buffer),
                latNE: region.center.latitude + region.span.latitudeDelta * (0.5 + buffer),
                lonNE: region.center.longitude + region.span.longitudeDelta * (0.5 + buffer)
            )
            Task { @MainActor in
                WindStationManager.shared.mapBBox = bbox
            }

            // Prefetch webcam thumbnails for visible + nearby regions
            prefetchNearbyWebcams(in: region)
        }

        /// Prefetch webcam thumbnails that are in or near the visible region
        private func prefetchNearbyWebcams(in region: MKCoordinateRegion) {
            let buffer = 1.0 // Extra buffer for prefetching
            let minLat = region.center.latitude - region.span.latitudeDelta * (0.5 + buffer)
            let maxLat = region.center.latitude + region.span.latitudeDelta * (0.5 + buffer)
            let minLon = region.center.longitude - region.span.longitudeDelta * (0.5 + buffer)
            let maxLon = region.center.longitude + region.span.longitudeDelta * (0.5 + buffer)

            // Filter webcams in the extended region
            let nearbyWebcams = parent.webcams.filter { webcam in
                webcam.latitude >= minLat && webcam.latitude <= maxLat &&
                webcam.longitude >= minLon && webcam.longitude <= maxLon
            }

            // Prefetch up to 20 nearby webcams
            if !nearbyWebcams.isEmpty {
                WebcamImageCache.shared.prefetchImages(for: Array(nearbyWebcams.prefix(20)))
            }
        }

        // Render tile overlays (sea map)
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Wind Station Annotation View

final class WindStationAnnotationView: MKAnnotationView {
    private let arrowBackground = UIView()
    private let arrowImageView = UIImageView()
    private let pillView = UIView()
    private let windLabel = UILabel()
    private let slashLabel = UILabel()
    private let gustLabel = UILabel()
    private let unitLabel = UILabel()
    private let spotIndicatorStack = UIStackView()

    private static let arrowImage: UIImage? = {
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        return UIImage(systemName: "arrow.up", withConfiguration: config)
    }()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        frame = CGRect(x: 0, y: 0, width: 68, height: 60)
        // Arrow center (y=11) is at the exact coordinate point
        centerOffset = CGPoint(x: 0, y: 19)
        backgroundColor = .clear
        isOpaque = false

        // Arrow background (semi-transparent dark) - at coordinate point
        arrowBackground.frame = CGRect(x: 23, y: 0, width: 22, height: 22)
        arrowBackground.layer.cornerRadius = 11
        arrowBackground.clipsToBounds = true
        arrowBackground.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        addSubview(arrowBackground)

        // Arrow
        arrowImageView.image = Self.arrowImage
        arrowImageView.tintColor = .white
        arrowImageView.contentMode = .center
        arrowImageView.frame = arrowBackground.bounds
        arrowBackground.addSubview(arrowImageView)

        // Pill background (semi-transparent dark)
        pillView.frame = CGRect(x: 0, y: 24, width: 68, height: 24)
        pillView.layer.cornerRadius = 12
        pillView.clipsToBounds = true
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        addSubview(pillView)

        // Labels - using Auto Layout for proper centering
        let stack = UIStackView(arrangedSubviews: [windLabel, slashLabel, gustLabel, unitLabel])
        stack.axis = .horizontal
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: pillView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: pillView.centerYAnchor)
        ])

        windLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        slashLabel.text = "/"
        slashLabel.font = UIFont.systemFont(ofSize: 9, weight: .semibold)
        slashLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        gustLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        unitLabel.text = WindUnit.current.symbol
        unitLabel.font = UIFont.systemFont(ofSize: 9, weight: .semibold)
        unitLabel.textColor = UIColor.white.withAlphaComponent(0.6)

        // Spot indicator dots below the pill
        spotIndicatorStack.axis = .horizontal
        spotIndicatorStack.spacing = 3
        spotIndicatorStack.alignment = .center
        spotIndicatorStack.translatesAutoresizingMaskIntoConstraints = false
        spotIndicatorStack.isHidden = true
        addSubview(spotIndicatorStack)

        NSLayoutConstraint.activate([
            spotIndicatorStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            spotIndicatorStack.topAnchor.constraint(equalTo: pillView.bottomAnchor, constant: 2)
        ])

    }

    func configure(with annotation: WindStationAnnotation) {
        // Force all view properties (in case of cached views)
        backgroundColor = .clear
        isOpaque = false
        arrowBackground.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        arrowBackground.isOpaque = false
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        pillView.isOpaque = false
        arrowImageView.tintColor = .white

        let wind = annotation.wind
        let gust = annotation.gust

        windLabel.text = "\(WindUnit.convertValue(wind))"
        windLabel.textColor = windScaleColor(wind)
        gustLabel.text = "\(WindUnit.convertValue(gust))"
        gustLabel.textColor = windScaleColor(gust)
        unitLabel.text = WindUnit.current.symbol

        // Rotate arrow
        arrowImageView.transform = CGAffineTransform(rotationAngle: (annotation.dirDeg + 180) * .pi / 180)

        // Reduce opacity for offline stations to indicate stale data
        alpha = annotation.isEffectivelyOnline ? 1.0 : 0.5

        // Selection state
        if annotation.isSelected {
            transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            zPriority = .max
        } else {
            transform = .identity
            zPriority = .defaultUnselected
        }

        // Nearby spot indicators — hide when zoomed in (spots visible on map)
        updateSpotIndicators(annotation)
    }

    private func updateSpotIndicators(_ annotation: WindStationAnnotation) {
        spotIndicatorStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Hide when zoomed in enough that spots are individually visible
        if !annotation.hasNearbySpots {
            spotIndicatorStack.isHidden = true
            return
        }

        spotIndicatorStack.isHidden = false

        if let color = annotation.nearbyKiteColor {
            spotIndicatorStack.addArrangedSubview(makeMiniSpotIcon(systemName: "figure.sailing", color: color))
        }
        if let color = annotation.nearbySurfColor {
            spotIndicatorStack.addArrangedSubview(makeMiniSpotIcon(systemName: "surfboard.fill", color: color))
        }
        if let color = annotation.nearbyParaglidingColor {
            spotIndicatorStack.addArrangedSubview(makeMiniSpotIcon(systemName: "arrow.up.right.circle.fill", color: color))
        }
    }

    private func makeMiniSpotIcon(systemName: String, color: UIColor) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: 16).isActive = true
        container.heightAnchor.constraint(equalToConstant: 16).isActive = true
        container.layer.cornerRadius = 8
        container.clipsToBounds = true
        container.backgroundColor = UIColor(white: 0.1, alpha: 0.7)

        let config = UIImage.SymbolConfiguration(pointSize: 7, weight: .semibold)
        let imageView = UIImageView(image: UIImage(systemName: systemName, withConfiguration: config))
        imageView.tintColor = color
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 10),
            imageView.heightAnchor.constraint(equalToConstant: 10)
        ])

        return container
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        transform = .identity
        alpha = 1.0
        // Reset backgrounds to prevent inconsistencies
        arrowBackground.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        // Reset spot indicators
        spotIndicatorStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        spotIndicatorStack.isHidden = true
    }
}

// MARK: - Cluster Annotation View

final class ClusterAnnotationView: MKAnnotationView {
    private let pillView = UIView()
    private let countLabel = UILabel()
    private let windIcon = UIImageView()
    private let windLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        frame = CGRect(x: 0, y: 0, width: 54, height: 24)
        centerOffset = CGPoint(x: 0, y: -12)
        backgroundColor = .clear

        // Pill background (semi-transparent dark)
        pillView.frame = bounds
        pillView.layer.cornerRadius = 12
        pillView.clipsToBounds = true
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        addSubview(pillView)

        // Stack for content
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: pillView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: pillView.centerYAnchor)
        ])

        // Count label
        countLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        countLabel.textColor = .white
        stack.addArrangedSubview(countLabel)

        // Station icon
        let config = UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        windIcon.image = UIImage(systemName: "antenna.radiowaves.left.and.right", withConfiguration: config)
        windIcon.tintColor = UIColor.white.withAlphaComponent(0.6)
        windIcon.contentMode = .scaleAspectFit
        stack.addArrangedSubview(windIcon)

        // Wind label
        windLabel.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        stack.addArrangedSubview(windLabel)
    }

    func configure(with cluster: MKClusterAnnotation) {
        // Force all view properties (in case of cached views)
        backgroundColor = .clear
        isOpaque = false
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        pillView.isOpaque = false

        let members = cluster.memberAnnotations
        let count = members.count

        // Display count
        countLabel.text = "\(count)"

        // Calculate average wind from all annotation types
        var totalWind: Double = 0
        var windCount = 0
        for member in members {
            if let station = member as? WindStationAnnotation {
                totalWind += station.wind
                windCount += 1
            }
        }

        let avgWind = windCount > 0 ? totalWind / Double(windCount) : 0
        windLabel.text = "\(Int(round(avgWind)))"
        windLabel.textColor = windScaleColor(avgWind)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Reset background to prevent inconsistencies
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
    }
}

// MARK: - Kite Spot Cluster Annotation View

final class KiteSpotClusterAnnotationView: MKAnnotationView {
    private let pillView = UIView()
    private let countLabel = UILabel()
    private let kiteIconView = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        frame = CGRect(x: 0, y: 0, width: 50, height: 26)
        centerOffset = CGPoint(x: 0, y: -13)
        backgroundColor = .clear

        pillView.frame = bounds
        pillView.layer.cornerRadius = 13
        pillView.clipsToBounds = true
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        addSubview(pillView)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 3
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: pillView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: pillView.centerYAnchor)
        ])

        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        kiteIconView.image = UIImage(systemName: "figure.sailing", withConfiguration: config)
        kiteIconView.tintColor = .white
        kiteIconView.contentMode = .scaleAspectFit
        stack.addArrangedSubview(kiteIconView)
        kiteIconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        kiteIconView.heightAnchor.constraint(equalToConstant: 16).isActive = true

        countLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        countLabel.textColor = .white
        stack.addArrangedSubview(countLabel)
    }

    func configure(with cluster: MKClusterAnnotation) {
        backgroundColor = .clear
        isOpaque = false
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)

        let members = cluster.memberAnnotations
        countLabel.text = "\(members.count)"

        // Couleur dominante par niveau
        var levelCounts: [SpotLevel: Int] = [:]
        for member in members {
            if let kiteSpot = member as? KiteSpotAnnotation {
                levelCounts[kiteSpot.level, default: 0] += 1
            }
        }

        let dominantLevel = levelCounts.max(by: { $0.value < $1.value })?.key ?? .intermediate

        let iconColor: UIColor
        switch dominantLevel {
        case .beginner:
            iconColor = UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1.0)
        case .intermediate:
            iconColor = UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1.0)
        case .advanced:
            iconColor = UIColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1.0)
        case .expert:
            iconColor = UIColor(red: 0.7, green: 0.4, blue: 0.9, alpha: 1.0)
        }
        kiteIconView.tintColor = iconColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        kiteIconView.tintColor = .white
    }
}

// MARK: - Kite Spot Annotation View

final class KiteSpotAnnotationView: MKAnnotationView {
    private let iconView = UIView()
    private let iconImageView = UIImageView()
    private var scoreBadge: UIView?
    private var scoreLabel: UILabel?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        centerOffset = CGPoint(x: 0, y: -14)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false

        iconView.frame = CGRect(x: 8, y: 8, width: 28, height: 28)
        iconView.layer.cornerRadius = 14
        iconView.clipsToBounds = true
        iconView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        addSubview(iconView)

        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        iconImageView.image = UIImage(systemName: "figure.sailing", withConfiguration: config)
        iconImageView.tintColor = .white
        iconImageView.contentMode = .center
        iconImageView.frame = iconView.bounds
        iconView.addSubview(iconImageView)
    }

    func configure(with annotation: KiteSpotAnnotation) {
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        iconView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)

        // Couleur par niveau
        let iconColor: UIColor
        switch annotation.level {
        case .beginner:
            iconColor = UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1.0)
        case .intermediate:
            iconColor = UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1.0)
        case .advanced:
            iconColor = UIColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1.0)
        case .expert:
            iconColor = UIColor(red: 0.7, green: 0.4, blue: 0.9, alpha: 1.0)
        }
        iconImageView.tintColor = iconColor

        // Update score badge
        if let score = annotation.score {
            showScore(score)
        } else {
            hideScore()
        }
    }

    func showScore(_ score: Int) {
        if scoreBadge == nil {
            let badge = UIView()
            let badgeFrame = CGRect(x: 26, y: 0, width: 18, height: 18)
            badge.frame = badgeFrame
            badge.layer.cornerRadius = 9
            badge.layer.borderWidth = 1.5
            badge.layer.borderColor = UIColor.white.cgColor
            badge.layer.shadowColor = UIColor.black.cgColor
            badge.layer.shadowOffset = CGSize(width: 0, height: 1)
            badge.layer.shadowRadius = 2
            badge.layer.shadowOpacity = 0.3
            badge.layer.shadowPath = UIBezierPath(roundedRect: badge.bounds, cornerRadius: 9).cgPath
            addSubview(badge)
            scoreBadge = badge

            let label = UILabel()
            label.font = UIFont.systemFont(ofSize: 9, weight: .bold)
            label.textColor = .white
            label.textAlignment = .center
            label.frame = badge.bounds
            badge.addSubview(label)
            scoreLabel = label
        }

        let badgeColor: UIColor
        if score >= 70 {
            badgeColor = UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1.0)
        } else if score >= 40 {
            badgeColor = UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        } else {
            badgeColor = UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0)
        }

        scoreBadge?.backgroundColor = badgeColor
        scoreLabel?.text = "\(score)"
        scoreBadge?.isHidden = false
    }

    func hideScore() {
        scoreBadge?.isHidden = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        iconImageView.tintColor = .white
        hideScore()
    }
}

// MARK: - Surf Spot Annotation View

final class SurfSpotAnnotationView: MKAnnotationView {
    private let iconView = UIView()
    private let iconImageView = UIImageView()
    private var scoreBadge: UIView?
    private var scoreLabel: UILabel?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        centerOffset = CGPoint(x: 0, y: -14)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false

        iconView.frame = CGRect(x: 8, y: 8, width: 28, height: 28)
        iconView.layer.cornerRadius = 14
        iconView.clipsToBounds = true
        iconView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        addSubview(iconView)

        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        iconImageView.image = UIImage(systemName: "surfboard.fill", withConfiguration: config)
        iconImageView.tintColor = .white
        iconImageView.contentMode = .center
        iconImageView.frame = iconView.bounds
        iconView.addSubview(iconImageView)
    }

    func configure(with annotation: SurfSpotAnnotation) {
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        iconView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)

        // Icon color based on level
        let iconColor: UIColor
        switch annotation.level {
        case .beginner:
            iconColor = UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1.0)
        case .intermediate:
            iconColor = UIColor(red: 1.0, green: 0.8, blue: 0.3, alpha: 1.0)
        case .advanced:
            iconColor = UIColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 1.0)
        case .expert:
            iconColor = UIColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
        }
        iconImageView.tintColor = iconColor

        // Update score badge
        if let score = annotation.score {
            showScore(score)
        } else {
            hideScore()
        }
    }

    func showScore(_ score: Int) {
        if scoreBadge == nil {
            let badge = UIView()
            let badgeFrame = CGRect(x: 26, y: 0, width: 18, height: 18)
            badge.frame = badgeFrame
            badge.layer.cornerRadius = 9
            badge.layer.borderWidth = 1.5
            badge.layer.borderColor = UIColor.white.cgColor
            badge.layer.shadowColor = UIColor.black.cgColor
            badge.layer.shadowOffset = CGSize(width: 0, height: 1)
            badge.layer.shadowRadius = 2
            badge.layer.shadowOpacity = 0.3
            badge.layer.shadowPath = UIBezierPath(roundedRect: badge.bounds, cornerRadius: 9).cgPath
            addSubview(badge)
            scoreBadge = badge

            let label = UILabel()
            label.font = UIFont.systemFont(ofSize: 9, weight: .bold)
            label.textColor = .white
            label.textAlignment = .center
            label.frame = badge.bounds
            badge.addSubview(label)
            scoreLabel = label
        }

        let badgeColor: UIColor
        if score >= 70 {
            badgeColor = UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1.0)
        } else if score >= 40 {
            badgeColor = UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        } else {
            badgeColor = UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0)
        }

        scoreBadge?.backgroundColor = badgeColor
        scoreLabel?.text = "\(score)"
        scoreBadge?.isHidden = false
    }

    func hideScore() {
        scoreBadge?.isHidden = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        iconImageView.tintColor = .white
        hideScore()
    }
}

// MARK: - Surf Spot Cluster Annotation View

final class SurfSpotClusterAnnotationView: MKAnnotationView {
    private let pillView = UIView()
    private let countLabel = UILabel()
    private let surfIconView = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        frame = CGRect(x: 0, y: 0, width: 50, height: 26)
        centerOffset = CGPoint(x: 0, y: -13)
        backgroundColor = .clear
        isOpaque = false

        pillView.frame = bounds
        pillView.layer.cornerRadius = 13
        pillView.clipsToBounds = true
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        addSubview(pillView)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 3
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: pillView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: pillView.centerYAnchor)
        ])

        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        surfIconView.image = UIImage(systemName: "surfboard.fill", withConfiguration: config)
        surfIconView.tintColor = .white
        surfIconView.contentMode = .scaleAspectFit
        stack.addArrangedSubview(surfIconView)
        surfIconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        surfIconView.heightAnchor.constraint(equalToConstant: 16).isActive = true

        countLabel.textColor = .white
        countLabel.font = .systemFont(ofSize: 13, weight: .bold)
        stack.addArrangedSubview(countLabel)
    }

    func configure(with cluster: MKClusterAnnotation) {
        backgroundColor = .clear
        isOpaque = false
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)

        let members = cluster.memberAnnotations
        countLabel.text = "\(members.count)"

        var levelCounts: [SurfLevel: Int] = [:]
        for member in members {
            if let surfSpot = member as? SurfSpotAnnotation {
                levelCounts[surfSpot.level, default: 0] += 1
            }
        }

        let dominantLevel = levelCounts.max(by: { $0.value < $1.value })?.key ?? .intermediate

        let iconColor: UIColor
        switch dominantLevel {
        case .beginner:
            iconColor = UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1.0)
        case .intermediate:
            iconColor = UIColor(red: 1.0, green: 0.8, blue: 0.3, alpha: 1.0)
        case .advanced:
            iconColor = UIColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 1.0)
        case .expert:
            iconColor = UIColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
        }
        surfIconView.tintColor = iconColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        surfIconView.tintColor = .white
    }
}

// MARK: - Paragliding Spot Annotation View

final class ParaglidingSpotAnnotationView: MKAnnotationView {
    private let iconView = UIView()
    private let iconImageView = UIImageView()
    private var scoreBadge: UIView?
    private var scoreLabel: UILabel?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        centerOffset = CGPoint(x: 0, y: -14)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false

        iconView.frame = CGRect(x: 8, y: 8, width: 28, height: 28)
        iconView.layer.cornerRadius = 14
        iconView.clipsToBounds = true
        iconView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        addSubview(iconView)

        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        iconImageView.image = UIImage(systemName: "arrow.up.right.circle.fill", withConfiguration: config)
        iconImageView.tintColor = .white
        iconImageView.contentMode = .center
        iconImageView.frame = iconView.bounds
        iconView.addSubview(iconImageView)
    }

    func configure(with annotation: ParaglidingSpotAnnotation) {
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        iconView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)

        // Color based on level
        let iconColor: UIColor
        if let level = annotation.level {
            switch level {
            case .ippi3:
                iconColor = UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1.0)
            case .ippi4:
                iconColor = UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1.0)
            case .ippi5:
                iconColor = UIColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1.0)
            }
        } else {
            iconColor = UIColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1.0) // Light blue default
        }
        iconImageView.tintColor = iconColor

        // Update score badge
        if let score = annotation.score {
            showScore(score)
        } else {
            hideScore()
        }
    }

    func showScore(_ score: Int) {
        if scoreBadge == nil {
            let badge = UIView()
            let badgeFrame = CGRect(x: 26, y: 0, width: 18, height: 18)
            badge.frame = badgeFrame
            badge.layer.cornerRadius = 9
            badge.layer.borderWidth = 1.5
            badge.layer.borderColor = UIColor.white.cgColor
            badge.layer.shadowColor = UIColor.black.cgColor
            badge.layer.shadowOffset = CGSize(width: 0, height: 1)
            badge.layer.shadowRadius = 2
            badge.layer.shadowOpacity = 0.3
            badge.layer.shadowPath = UIBezierPath(roundedRect: badge.bounds, cornerRadius: 9).cgPath
            addSubview(badge)
            scoreBadge = badge

            let label = UILabel()
            label.font = UIFont.systemFont(ofSize: 9, weight: .bold)
            label.textColor = .white
            label.textAlignment = .center
            label.frame = badge.bounds
            badge.addSubview(label)
            scoreLabel = label
        }

        let badgeColor: UIColor
        if score >= 70 {
            badgeColor = UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1.0)
        } else if score >= 40 {
            badgeColor = UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        } else {
            badgeColor = UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0)
        }

        scoreBadge?.backgroundColor = badgeColor
        scoreLabel?.text = "\(score)"
        scoreBadge?.isHidden = false
    }

    func hideScore() {
        scoreBadge?.isHidden = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        iconImageView.tintColor = .white
        hideScore()
    }
}

// MARK: - Paragliding Spot Cluster Annotation View

final class ParaglidingSpotClusterAnnotationView: MKAnnotationView {
    private let pillView = UIView()
    private let countLabel = UILabel()
    private let paraIconView = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        frame = CGRect(x: 0, y: 0, width: 50, height: 26)
        centerOffset = CGPoint(x: 0, y: -13)
        backgroundColor = .clear
        isOpaque = false

        pillView.frame = bounds
        pillView.layer.cornerRadius = 13
        pillView.clipsToBounds = true
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        addSubview(pillView)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 3
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: pillView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: pillView.centerYAnchor)
        ])

        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        paraIconView.image = UIImage(systemName: "arrow.up.right.circle.fill", withConfiguration: config)
        paraIconView.tintColor = .white
        paraIconView.contentMode = .scaleAspectFit
        stack.addArrangedSubview(paraIconView)
        paraIconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        paraIconView.heightAnchor.constraint(equalToConstant: 16).isActive = true

        countLabel.textColor = .white
        countLabel.font = .systemFont(ofSize: 13, weight: .bold)
        stack.addArrangedSubview(countLabel)
    }

    func configure(with cluster: MKClusterAnnotation) {
        backgroundColor = .clear
        isOpaque = false
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)

        let members = cluster.memberAnnotations
        countLabel.text = "\(members.count)"

        // Color based on dominant level
        var levelCounts: [ParaglidingLevel: Int] = [:]
        for member in members {
            if let spot = member as? ParaglidingSpotAnnotation, let level = spot.level {
                levelCounts[level, default: 0] += 1
            }
        }

        let dominantLevel = levelCounts.max(by: { $0.value < $1.value })?.key

        let iconColor: UIColor
        if let level = dominantLevel {
            switch level {
            case .ippi3:
                iconColor = UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1.0)
            case .ippi4:
                iconColor = UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1.0)
            case .ippi5:
                iconColor = UIColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1.0)
            }
        } else {
            iconColor = UIColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1.0)
        }
        paraIconView.tintColor = iconColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        paraIconView.tintColor = .white
    }
}

// MARK: - Webcam Annotation View (Windy-style thumbnail)

final class WebcamAnnotationView: MKAnnotationView {
    private let cardView = UIView()
    private let imageView = UIImageView()
    private let statusBar = UIView()
    private let statusDot = UIView()
    private let timestampLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let placeholderIcon = UIImageView()

    private var currentImageUrl: String?
    private var imageTimestamp: Date?

    // Static image cache shared across all annotation views
    private static var imageCache = NSCache<NSString, UIImage>()
    private static var imageTimestamps = [String: Date]()

    private static let cameraIcon: UIImage? = {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        return UIImage(systemName: "video.fill", withConfiguration: config)
    }()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        // Card size like Windy
        frame = CGRect(x: 0, y: 0, width: 110, height: 75)
        centerOffset = CGPoint(x: 0, y: -37)
        backgroundColor = .clear
        isOpaque = false

        // Card container with shadow
        cardView.frame = bounds
        cardView.layer.cornerRadius = 8
        cardView.clipsToBounds = true
        cardView.backgroundColor = UIColor(white: 0.15, alpha: 0.9)
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOffset = CGSize(width: 0, height: 2)
        cardView.layer.shadowRadius = 4
        cardView.layer.shadowOpacity = 0.3
        cardView.layer.masksToBounds = false
        addSubview(cardView)

        // Image view (fills most of the card) with rounded top corners
        imageView.frame = CGRect(x: 0, y: 0, width: 110, height: 55)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor(white: 0.2, alpha: 1)
        imageView.layer.cornerRadius = 8
        imageView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        cardView.addSubview(imageView)

        // Placeholder icon (shown while loading)
        placeholderIcon.image = Self.cameraIcon
        placeholderIcon.tintColor = UIColor.white.withAlphaComponent(0.4)
        placeholderIcon.contentMode = .center
        placeholderIcon.frame = imageView.bounds
        imageView.addSubview(placeholderIcon)

        // Loading indicator
        loadingIndicator.color = .white
        loadingIndicator.center = CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY)
        loadingIndicator.hidesWhenStopped = true
        imageView.addSubview(loadingIndicator)

        // Status bar at bottom with rounded bottom corners
        statusBar.frame = CGRect(x: 0, y: 55, width: 110, height: 20)
        statusBar.backgroundColor = UIColor(white: 0.1, alpha: 0.95)
        statusBar.layer.cornerRadius = 8
        statusBar.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        cardView.addSubview(statusBar)

        // Green status dot
        statusDot.frame = CGRect(x: 8, y: 6, width: 8, height: 8)
        statusDot.layer.cornerRadius = 4
        statusDot.backgroundColor = UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 1)
        statusBar.addSubview(statusDot)

        // Timestamp label
        timestampLabel.frame = CGRect(x: 20, y: 0, width: 85, height: 20)
        timestampLabel.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        timestampLabel.textColor = .white
        timestampLabel.text = "En direct"
        statusBar.addSubview(timestampLabel)

        // Border
        cardView.layer.borderWidth = 0.5
        cardView.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
    }

    @discardableResult
    func configure(with annotation: WebcamAnnotation) -> Bool {
        backgroundColor = .clear
        isOpaque = false

        let isNewWebcam = currentImageUrl != annotation.thumbnailUrl

        // Check if image already loaded and cached
        let cacheKey = annotation.thumbnailUrl as NSString
        if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
            imageView.image = cachedImage
            placeholderIcon.isHidden = true
            loadingIndicator.stopAnimating()

            // Update timestamp from cache
            if let timestamp = Self.imageTimestamps[annotation.thumbnailUrl] {
                imageTimestamp = timestamp
                updateTimestamp()
            }
            currentImageUrl = annotation.thumbnailUrl

            // Refresh in background to update image + timestamp
            refreshInBackground(url: annotation.thumbnailUrl)
        } else if isNewWebcam {
            // Start loading new image
            currentImageUrl = annotation.thumbnailUrl
            loadImage(url: annotation.thumbnailUrl)
        }

        return isNewWebcam
    }

    /// Background refresh for already-cached webcams (updates image + timestamp)
    private func refreshInBackground(url: String) {
        Task { @MainActor in
            guard let fresh = await WebcamImageCache.shared.fetchFreshThumbnail(from: url),
                  self.currentImageUrl == url,
                  let freshImage = UIImage(data: fresh.data) else { return }

            Self.imageCache.setObject(freshImage, forKey: url as NSString)
            if let timestamp = fresh.timestamp {
                Self.imageTimestamps[url] = timestamp
            }
            self.imageView.image = freshImage
            self.imageTimestamp = fresh.timestamp
            self.updateTimestamp()
        }
    }

    // Pop-in animation when view appears
    func animateAppearance() {
        // Start small and transparent
        cardView.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        cardView.alpha = 0

        // Spring animation for pop effect
        UIView.animate(
            withDuration: 0.4,
            delay: Double.random(in: 0...0.15), // Stagger effect
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.8,
            options: [.curveEaseOut],
            animations: {
                self.cardView.transform = .identity
                self.cardView.alpha = 1
            }
        )
    }

    private func loadImage(url: String) {
        placeholderIcon.isHidden = false
        loadingIndicator.startAnimating()
        imageView.image = nil

        Task { @MainActor in
            // Step 1: Show cached image immediately (fast path)
            if let result = await WebcamImageCache.shared.loadThumbnailWithTimestamp(from: url),
               self.currentImageUrl == url,
               let image = UIImage(data: result.data) {
                Self.imageCache.setObject(image, forKey: url as NSString)
                if let timestamp = result.timestamp {
                    Self.imageTimestamps[url] = timestamp
                }
                self.imageView.alpha = 0
                self.imageView.image = image
                self.placeholderIcon.isHidden = true
                self.loadingIndicator.stopAnimating()
                self.imageTimestamp = result.timestamp
                self.updateTimestamp()
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                    self.imageView.alpha = 1
                }
            }

            // Step 2: Fetch fresh image + timestamp from network
            guard self.currentImageUrl == url,
                  let fresh = await WebcamImageCache.shared.fetchFreshThumbnail(from: url),
                  let freshImage = UIImage(data: fresh.data) else {
                if self.imageView.image == nil {
                    self.loadingIndicator.stopAnimating()
                    self.imageTimestamp = nil
                    self.updateTimestamp()
                }
                return
            }

            // Update image and timestamp with fresh data
            Self.imageCache.setObject(freshImage, forKey: url as NSString)
            if let timestamp = fresh.timestamp {
                Self.imageTimestamps[url] = timestamp
            }
            self.imageView.image = freshImage
            self.placeholderIcon.isHidden = true
            self.loadingIndicator.stopAnimating()
            self.imageTimestamp = fresh.timestamp
            self.updateTimestamp()
        }
    }

    private func updateTimestamp() {
        guard let imageTimestamp = imageTimestamp else {
            // Unknown timestamp - show gray indicator
            timestampLabel.text = "—"
            statusDot.backgroundColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1) // Gray
            return
        }

        let elapsed = Int(-imageTimestamp.timeIntervalSinceNow)

        // Handle future timestamps (clock skew)
        if elapsed < 0 {
            timestampLabel.text = "À l'instant"
            statusDot.backgroundColor = UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 1)
            return
        }

        // Update LED color based on image age
        if elapsed < 3600 {
            // Less than 1 hour - green
            statusDot.backgroundColor = UIColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 1)
        } else if elapsed < 10800 {
            // 1-3 hours - orange
            statusDot.backgroundColor = UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1)
        } else {
            // More than 3 hours - red
            statusDot.backgroundColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1)
        }

        // Update timestamp text
        if elapsed < 120 {
            timestampLabel.text = "À l'instant"
        } else if elapsed < 3600 {
            let minutes = elapsed / 60
            timestampLabel.text = "Il y a \(minutes) min"
        } else if elapsed < 86400 {
            let hours = elapsed / 3600
            timestampLabel.text = "Il y a \(hours) h"
        } else {
            let days = elapsed / 86400
            timestampLabel.text = "Il y a \(days) j"
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        imageView.alpha = 1
        placeholderIcon.isHidden = false
        loadingIndicator.stopAnimating()
        currentImageUrl = nil
        imageTimestamp = nil
        timestampLabel.text = "—"
        statusDot.backgroundColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1) // Gray for unknown
        // Reset transform for reuse
        cardView.transform = .identity
        cardView.alpha = 1
    }
}

// MARK: - Wave Buoy Annotation View

final class WaveBuoyAnnotationView: MKAnnotationView {
    private let waveBackground = UIView()
    private let waveIcon = UIImageView()
    private let pillView = UIView()
    private let heightLabel = UILabel()
    private let periodLabel = UILabel()
    private let unitLabel = UILabel()

    private static let waveImage: UIImage? = {
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        return UIImage(systemName: "water.waves", withConfiguration: config)
    }()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView()
    }

    private func setupView() {
        frame = CGRect(x: 0, y: 0, width: 70, height: 48)
        centerOffset = CGPoint(x: 0, y: 13)
        backgroundColor = .clear
        isOpaque = false

        // Wave icon background (circular, at coordinate point)
        waveBackground.frame = CGRect(x: 24, y: 0, width: 22, height: 22)
        waveBackground.layer.cornerRadius = 11
        waveBackground.clipsToBounds = true
        waveBackground.backgroundColor = UIColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 0.9)
        addSubview(waveBackground)

        // Wave icon
        waveIcon.image = Self.waveImage
        waveIcon.tintColor = .white
        waveIcon.contentMode = .center
        waveIcon.frame = waveBackground.bounds
        waveBackground.addSubview(waveIcon)

        // Pill background for wave data
        pillView.frame = CGRect(x: 0, y: 24, width: 70, height: 24)
        pillView.layer.cornerRadius = 12
        pillView.clipsToBounds = true
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        addSubview(pillView)

        // Labels using Auto Layout
        let stack = UIStackView(arrangedSubviews: [heightLabel, periodLabel, unitLabel])
        stack.axis = .horizontal
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: pillView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: pillView.centerYAnchor)
        ])

        // Height label (main value)
        heightLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        heightLabel.textColor = .white

        // Period label
        periodLabel.font = UIFont.systemFont(ofSize: 9, weight: .semibold)
        periodLabel.textColor = UIColor.white.withAlphaComponent(0.6)

        // Unit label
        unitLabel.text = "m"
        unitLabel.font = UIFont.systemFont(ofSize: 9, weight: .semibold)
        unitLabel.textColor = UIColor.white.withAlphaComponent(0.6)
    }

    func configure(with annotation: WaveBuoyAnnotation) {
        backgroundColor = .clear
        isOpaque = false
        waveBackground.isOpaque = false
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
        pillView.isOpaque = false

        // Wave height display
        if let hm0 = annotation.hm0 {
            heightLabel.text = String(format: "%.1f", hm0)
            heightLabel.textColor = annotation.waveColor

            // Update wave icon background to match wave intensity
            waveBackground.backgroundColor = annotation.waveColor.withAlphaComponent(0.9)
        } else {
            heightLabel.text = "—"
            heightLabel.textColor = UIColor.white.withAlphaComponent(0.5)
            waveBackground.backgroundColor = UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 0.9)
        }

        // Period display
        if let tp = annotation.tp {
            periodLabel.text = String(format: "/%.1fs", tp)
        } else {
            periodLabel.text = ""
        }

        // Opacity based on online status
        alpha = annotation.isOnline ? 1.0 : 0.5
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        alpha = 1.0
        waveBackground.backgroundColor = UIColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 0.9)
        pillView.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
    }
}
