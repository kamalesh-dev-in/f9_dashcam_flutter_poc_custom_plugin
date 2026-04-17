import Flutter
import MetalKit

/// PlatformView that hosts an MTKView for Metal rendering.
/// Also acts as MTKViewDelegate to present frames on the main thread (display-synced).
class DashcamPlatformView: NSObject, FlutterPlatformView, MTKViewDelegate {

    private var metalView: MTKView
    private static var registry: [Int64: DashcamPlatformView] = [:]

    /// Reference to the native bridge for drawing frames
    private var bridge: DashcamNativeBridge?

    init(frame: CGRect, viewId: Int64) {
        // Create Metal Kit View
        metalView = MTKView(frame: frame)
        if let device = MTLCreateSystemDefaultDevice() {
            metalView.device = device
        }
        metalView.isPaused = true  // We control drawing via needsDisplay
        metalView.enableSetNeedsDisplay = true
        metalView.contentMode = .scaleAspectFit
        metalView.backgroundColor = .black

        super.init()

        metalView.delegate = self

        // Register for lookup by viewId
        DashcamPlatformView.registry[viewId] = self
    }

    func view() -> UIView {
        return metalView
    }

    /// Get the MTKView for a given viewId
    static func get(_ viewId: Int64) -> DashcamPlatformView? {
        return registry[viewId]
    }

    /// Get the underlying MTKView
    func getMetalView() -> MTKView {
        return metalView
    }

    /// Set the native bridge for drawing (called after nativeCreate)
    func setBridge(_ bridge: DashcamNativeBridge) {
        self.bridge = bridge
    }

    /// Remove from registry
    static func unregister(_ viewId: Int64) {
        registry.removeValue(forKey: viewId)
    }

    // MARK: - MTKViewDelegate

    func draw(in view: MTKView) {
        bridge?.drawRenderer()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // No action needed
    }
}
