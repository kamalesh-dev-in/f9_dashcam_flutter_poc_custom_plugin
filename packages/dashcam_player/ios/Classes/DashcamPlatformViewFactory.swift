import Flutter

/// Factory that creates DashcamPlatformView instances for Flutter.
class DashcamPlatformViewFactory: NSObject, FlutterPlatformViewFactory {

    func create(withFrame frame: CGRect,
                viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        return DashcamPlatformView(frame: frame, viewId: viewId)
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}
