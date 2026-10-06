/// Watch debug surfaces (Debug tab, screen-size preview, debug discard) exist only in the `Dev`
/// build configuration (compile flag `RPPL_DEV`, see Docs/DevWorkflow.md). Never in Debug,
/// TestFlight, or App Store builds.
enum WatchDebugTools {
    static var isEnabled: Bool {
        #if RPPL_DEV
        true
        #else
        false
        #endif
    }
}
