import ARKit
import CoreImage
import MimamoriCore
import SceneKit
import SwiftUI

/// The ARKit side of "毎朝の笑顔": the front camera with face tracking. Each face update's blend
/// shapes become the plain dictionary `SmileScorer` reads, and when `SmileGate` says the smile held,
/// the frame of that moment is taken as a small JPEG. Nothing leaves this view but that JPEG and its
/// score; the photo goes only to the family (never to Claude).
enum SmileCamera {
  /// Face tracking needs the TrueDepth camera (the Face ID iPhones). The simulator has none.
  static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

  /// ARKit's names are enum cases; their raw values are not the names `SmileScorer` uses, so each
  /// case is mapped by hand.
  static let keys: [(ARFaceAnchor.BlendShapeLocation, String)] = [
    (.mouthSmileLeft, SmileScorer.Key.mouthSmileLeft),
    (.mouthSmileRight, SmileScorer.Key.mouthSmileRight),
    (.cheekSquintLeft, SmileScorer.Key.cheekSquintLeft),
    (.cheekSquintRight, SmileScorer.Key.cheekSquintRight),
  ]

  static func shapes(of anchor: ARFaceAnchor) -> [String: Float] {
    var out: [String: Float] = [:]
    for (location, key) in keys {
      if let value = anchor.blendShapes[location] { out[key] = value.floatValue }
    }
    return out
  }

  private static let context = CIContext()

  /// The camera frame turned upright for a phone held in portrait, scaled to at most 640 pixels on
  /// the long side, as JPEG. The server takes up to 500 KB; this is usually far less.
  static func jpeg(from buffer: CVPixelBuffer) -> Data? {
    let image = CIImage(cvPixelBuffer: buffer).oriented(.right)
    let longSide = max(image.extent.width, image.extent.height)
    let scale = min(1, 640 / longSide)
    let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    return context.jpegRepresentation(
      of: scaled, colorSpace: space,
      options: [
        CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String):
          0.7
      ])
  }
}

/// The live preview. Calls `onSmile` once, on the main actor, with the JPEG and the score.
struct SmileCameraPreview: UIViewRepresentable {
  let onSmile: @MainActor (Data, Double) -> Void

  func makeCoordinator() -> Tracker { Tracker(onSmile: onSmile) }

  func makeUIView(context: Context) -> ARSCNView {
    let view = ARSCNView()
    view.automaticallyUpdatesLighting = true
    view.session.delegate = context.coordinator
    let configuration = ARFaceTrackingConfiguration()
    configuration.isLightEstimationEnabled = false
    view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    return view
  }

  static func dismantleUIView(_ view: ARSCNView, coordinator: Tracker) {
    view.session.pause()
  }

  func updateUIView(_ view: ARSCNView, context: Context) {}

  /// ARKit calls the delegate on the main queue (no `delegateQueue` is set), so the gate is only
  /// touched there; that is what makes `@unchecked Sendable` hold.
  final class Tracker: NSObject, ARSessionDelegate, @unchecked Sendable {
    private var gate = SmileGate()
    private let onSmile: @MainActor (Data, Double) -> Void

    init(onSmile: @escaping @MainActor (Data, Double) -> Void) {
      self.onSmile = onSmile
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
      guard let face = anchors.lazy.compactMap({ $0 as? ARFaceAnchor }).first, face.isTracked else {
        return
      }
      let shapes = SmileCamera.shapes(of: face)
      guard let score = gate.feed(shapes) else { return }
      guard let buffer = session.currentFrame?.capturedImage, let jpeg = SmileCamera.jpeg(from: buffer) else {
        // No frame to take: wait for the next held smile.
        gate = SmileGate()
        return
      }
      session.pause()
      MainActor.assumeIsolated { onSmile(jpeg, score) }
    }
  }
}
