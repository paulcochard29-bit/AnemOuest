import UIKit

// MARK: - Haptic Manager

/// Centralized haptic feedback manager with pre-warmed generators
final class HapticManager {
    static let shared = HapticManager()

    // Pre-initialized generators for instant response
    private let lightGenerator: UIImpactFeedbackGenerator
    private let mediumGenerator: UIImpactFeedbackGenerator
    private let heavyGenerator: UIImpactFeedbackGenerator
    private let selectionGenerator: UISelectionFeedbackGenerator
    private let notificationGenerator: UINotificationFeedbackGenerator

    private init() {
        lightGenerator = UIImpactFeedbackGenerator(style: .light)
        mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
        heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
        selectionGenerator = UISelectionFeedbackGenerator()
        notificationGenerator = UINotificationFeedbackGenerator()

        // Pre-warm all generators
        prepareAll()
    }

    // MARK: - Impact Feedback

    /// Light tap - for subtle interactions (toggles, small buttons)
    func light() {
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
    }

    /// Light tap with custom intensity (0.0 - 1.0)
    func light(intensity: CGFloat) {
        lightGenerator.impactOccurred(intensity: intensity)
        lightGenerator.prepare()
    }

    /// Medium tap - for standard actions (button presses, selections)
    func medium() {
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
    }

    /// Heavy tap - for important actions (confirmations, completions)
    func heavy() {
        heavyGenerator.impactOccurred()
        heavyGenerator.prepare()
    }

    // MARK: - Selection Feedback

    /// Selection changed - for scrolling through items, sliders
    func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    // MARK: - Notification Feedback

    /// Success - task completed successfully
    func success() {
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
    }

    /// Warning - something needs attention
    func warning() {
        notificationGenerator.notificationOccurred(.warning)
        notificationGenerator.prepare()
    }

    /// Error - something went wrong
    func error() {
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
    }

    // MARK: - Prepare

    /// Pre-warm all generators (call when view appears)
    func prepareAll() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
        heavyGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }
}

// MARK: - Convenience Extensions

extension HapticManager {
    /// Haptic for opening a sheet/modal
    func openSheet() {
        light(intensity: 0.6)
    }

    /// Haptic for closing a sheet/modal
    func closeSheet() {
        light(intensity: 0.4)
    }

    /// Haptic for refreshing data
    func refresh() {
        light(intensity: 0.5)
    }

    /// Haptic for selecting an item on map
    func mapSelection() {
        medium()
    }

    /// Haptic for toggling a switch/favorite
    func toggle() {
        light(intensity: 0.7)
    }

    /// Haptic for slider value change
    func sliderTick() {
        selection()
    }
}
