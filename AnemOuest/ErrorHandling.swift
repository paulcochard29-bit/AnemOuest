import SwiftUI
import Combine

// MARK: - App Error Types

enum AppError: LocalizedError, Identifiable {
    case networkUnavailable
    case stationsFetchFailed(Int, Int) // succeeded, total
    case forecastFailed(String)
    case tideFailed
    case waveBuoysFailed
    case cacheSaveFailed

    var id: String { localizedDescription }

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Connexion indisponible"
        case .stationsFetchFailed(let ok, let total):
            return "\(total - ok)/\(total) stations injoignables"
        case .forecastFailed(let name):
            return "Prévisions indisponibles pour \(name)"
        case .tideFailed:
            return "Données de marée indisponibles"
        case .waveBuoysFailed:
            return "Bouées indisponibles"
        case .cacheSaveFailed:
            return "Erreur de cache"
        }
    }

    var errorType: String {
        switch self {
        case .networkUnavailable: return "network"
        case .stationsFetchFailed: return "stations"
        case .forecastFailed: return "forecast"
        case .tideFailed: return "tide"
        case .waveBuoysFailed: return "waveBuoys"
        case .cacheSaveFailed: return "cache"
        }
    }

    var icon: String {
        switch self {
        case .networkUnavailable: return "wifi.slash"
        case .stationsFetchFailed: return "sensor.fill"
        case .forecastFailed: return "cloud.sun"
        case .tideFailed: return "water.waves"
        case .waveBuoysFailed: return "wave.3.right"
        case .cacheSaveFailed: return "externaldrive.badge.exclamationmark"
        }
    }

    var severity: ErrorSeverity {
        switch self {
        case .networkUnavailable: return .warning
        case .stationsFetchFailed: return .info
        case .forecastFailed: return .info
        case .tideFailed: return .info
        case .waveBuoysFailed: return .info
        case .cacheSaveFailed: return .info
        }
    }
}

enum ErrorSeverity {
    case info
    case warning

    var color: Color {
        switch self {
        case .info: return .orange
        case .warning: return .red
        }
    }
}

// MARK: - Error Manager

@MainActor
final class ErrorManager: ObservableObject {
    static let shared = ErrorManager()

    @Published var currentError: AppError?
    @Published var isShowingError: Bool = false

    private var dismissTask: Task<Void, Never>?

    func show(_ error: AppError) {
        // Avoid duplicate errors
        if isShowingError, currentError?.localizedDescription == error.localizedDescription {
            return
        }

        dismissTask?.cancel()
        currentError = error
        Analytics.errorShown(type: error.errorType)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isShowingError = true
        }

        // Auto-dismiss after 4 seconds
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            isShowingError = false
        }
        // Clear error after animation
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            currentError = nil
        }
    }
}

// MARK: - Error Banner View

struct ErrorBannerView: View {
    @ObservedObject var errorManager = ErrorManager.shared

    var body: some View {
        if errorManager.isShowingError, let error = errorManager.currentError {
            HStack(spacing: 10) {
                Image(systemName: error.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(error.severity.color)

                Text(error.localizedDescription)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Button {
                    errorManager.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(error.severity.color.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
