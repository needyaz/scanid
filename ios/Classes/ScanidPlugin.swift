import Flutter
import UIKit
import Vision

/// On-device OCR/barcode/document-detect over the `scanid/capture`
/// MethodChannel, backed by Apple Vision. Mirrors the contract
/// `PlatformCaptureService` (Dart) expects: `recognizeText` takes
/// `{ image: <bytes> }` and returns a list of
/// `{ text: String, confidence: Double, box: {...} }` lines. Nothing leaves
/// the device.
public class ScanidPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "scanid/capture",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(ScanidPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let data = (args["image"] as? FlutterStandardTypedData)?.data,
      let image = UIImage(data: data),
      let cgImage = image.cgImage
    else {
      if call.method == "recognizeText" || call.method == "recognizeBarcodes"
        || call.method == "detectDocumentRect" {
        reply(result, FlutterError(code: "bad_image", message: "Could not decode image", details: nil))
      } else {
        reply(result, FlutterMethodNotImplemented)
      }
      return
    }

    switch call.method {
    case "recognizeText": recognizeText(cgImage, result)
    case "recognizeBarcodes": recognizeBarcodes(cgImage, result)
    case "detectDocumentRect":
      if #available(iOS 15.0, *) {
        detectDocumentRect(cgImage, result)
      } else {
        reply(result, nil) // no document segmentation pre-iOS 15 — the caller crops manually
      }
    default: reply(result, FlutterMethodNotImplemented)
    }
  }

  // Flutter requires channel replies on the main (platform) thread; the Vision
  // completion handlers below run on a background queue (see `perform`), so hop
  // every reply to main.
  private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  // Detect the document in the image and return its bounding box, normalized to
  // [0,1] with a top-left origin (to seed a confirm-crop UI) — or nil when
  // none is found. The caller should confirm/adjust the rect, so this is only
  // a hint; no crop is applied here. Segmentation is iOS 15+.
  @available(iOS 15.0, *)
  private func detectDocumentRect(_ cgImage: CGImage, _ result: @escaping FlutterResult) {
    let request = VNDetectDocumentSegmentationRequest { request, error in
      guard error == nil,
        let obs = (request.results as? [VNRectangleObservation])?.first
      else {
        self.reply(result, nil) // no document → caller offers a manual crop
        return
      }
      // boundingBox is normalized with a bottom-left origin; flip Y to top-left.
      let bb = obs.boundingBox
      self.reply(result, [
        "left": Double(bb.minX),
        "top": Double(1.0 - bb.maxY),
        "width": Double(bb.width),
        "height": Double(bb.height),
      ])
    }
    perform(request, on: cgImage, result: result)
  }

  private func recognizeText(_ cgImage: CGImage, _ result: @escaping FlutterResult) {
    let request = VNRecognizeTextRequest { request, error in
      if let error = error {
        self.reply(result, FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil))
        return
      }
      let observations = request.results as? [VNRecognizedTextObservation] ?? []
      let lines: [[String: Any]] = observations.compactMap { obs in
        guard let top = obs.topCandidates(1).first else { return nil }
        // boundingBox is normalized, bottom-left origin — flip Y to top-left.
        let bb = obs.boundingBox
        return [
          "text": top.string,
          "confidence": Double(top.confidence),
          "box": [
            "left": Double(bb.minX),
            "top": Double(1.0 - bb.maxY),
            "width": Double(bb.width),
            "height": Double(bb.height),
          ],
        ]
      }
      self.reply(result, lines)
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    perform(request, on: cgImage, result: result)
  }

  // Decode 2D barcodes — chiefly a driver license's PDF417 (the AAMVA payload).
  private func recognizeBarcodes(_ cgImage: CGImage, _ result: @escaping FlutterResult) {
    let request = VNDetectBarcodesRequest { request, error in
      if error != nil {
        self.reply(result, [String]())
        return
      }
      let observations = request.results as? [VNBarcodeObservation] ?? []
      let payloads: [String] = observations.compactMap { $0.payloadStringValue }
      self.reply(result, payloads)
    }
    // Detect all symbologies (driver licenses are PDF417). Not restricting helps
    // some Vision revisions that ignore an explicit PDF417-only filter.
    perform(request, on: cgImage, result: result)
  }

  private func perform(_ request: VNImageBasedRequest, on cgImage: CGImage,
                       result: @escaping FlutterResult) {
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
      } catch {
        self.reply(result, FlutterError(code: "capture_failed", message: error.localizedDescription, details: nil))
      }
    }
  }
}
