import SwiftUI
import MapKit

struct WatchMapView: View {
    @EnvironmentObject var data: WatchDataManager
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.5, longitude: -3.5),
            span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)
        )
    )
    @State private var hasLoaded = false

    var body: some View {
        ZStack {
            Map(position: $position) {
                // Wind stations
                ForEach(data.allStations.filter(\.isOnline)) { station in
                    if let coord = station.coordinate {
                        Annotation(station.name, coordinate: coord) {
                            StationMarker(station: station)
                        }
                    }
                }

                // Wave buoys
                ForEach(data.buoys) { buoy in
                    Annotation(buoy.name, coordinate: buoy.coordinate) {
                        BuoyMarker(buoy: buoy)
                    }
                }
            }
            .mapStyle(.standard)
            .mapControlVisibility(.hidden)

            // Legend
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    LegendDot(color: .cyan, label: "Vent")
                    LegendDot(color: .blue, label: "Houle")
                }
                .font(.system(size: 9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 4)
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            async let _ = data.fetchStationsForMap()
            async let _ = data.fetchBuoys()
        }
    }
}

// MARK: - Station Marker

struct StationMarker: View {
    let station: WatchStation

    var body: some View {
        VStack(spacing: 0) {
            Text("\(station.windInt)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(station.windColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // Arrow pointing down
            Triangle()
                .fill(station.windColor)
                .frame(width: 6, height: 4)
        }
    }
}

// MARK: - Buoy Marker

struct BuoyMarker: View {
    let buoy: WatchBuoy

    var body: some View {
        VStack(spacing: 0) {
            Text(buoy.heightText)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
                .background(buoy.waveColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Triangle()
                .fill(buoy.waveColor)
                .frame(width: 6, height: 4)
        }
    }
}

// MARK: - Helpers

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}

struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}
