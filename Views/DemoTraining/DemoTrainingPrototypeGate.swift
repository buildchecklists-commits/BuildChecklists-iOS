import Foundation

/// Product gate for DEMO training.
///
/// Training is a product feature of the DEMO session: every caller still checks
/// `store.isDemoMode` (never shown in a registered/normal profile) and nothing starts
/// automatically on DEMO entry — the user opens it from the «Обучение» entry.
///
/// The type keeps its historical name to limit churn; it no longer depends on a launch argument.
/// Only the visual gallery below is a DEBUG-only diagnostic.
enum DemoTrainingPrototypeGate {
    /// Product training is available whenever the session is DEMO (callers add the `isDemoMode` check).
    static var isEnabled: Bool { true }

    /// DEBUG-only chrome gallery for visual review (`-DemoTrainingGallery`); never used in ordinary launches.
    static var showsPreviewGallery: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DemoTrainingGallery")
        #else
        false
        #endif
    }
}
