package io.needyaz.scanid

import android.graphics.BitmapFactory
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/// On-device OCR/barcode over the `scanid/capture` MethodChannel, backed by ML
/// Kit. Mirrors the contract `PlatformCaptureService` (Dart) expects:
/// `recognizeText` takes `{ image: <bytes> }` and returns a list of
/// `{ text: String, confidence: Double, box: {...} }` lines. Nothing leaves
/// the device.
class ScanidPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    // Background work that must never run on the platform thread: bitmap
    // decodes (a 12 MP capture is ~48 MB + 100-500 ms of synchronous decode).
    // Replies hop back to the UI thread via result.success — safe to call off
    // the platform thread for a MethodChannel.Result.
    private val workScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // ML Kit detectors hold native resources; getClient() per call leaks one
    // each time. Create each once and reuse it across calls, closing on
    // detach. Held via the lazy delegate so detach can skip (not instantiate)
    // an unused one.
    private val textRecognizerLazy =
        lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }
    private val textRecognizer by textRecognizerLazy
    private val barcodeScannerLazy = lazy {
        // Decode 2D barcodes — chiefly a driver license's PDF417.
        BarcodeScanning.getClient(
            BarcodeScannerOptions.Builder()
                .setBarcodeFormats(
                    Barcode.FORMAT_PDF417,
                    Barcode.FORMAT_QR_CODE,
                    Barcode.FORMAT_AZTEC,
                )
                .build()
        )
    }
    private val barcodeScanner by barcodeScannerLazy

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "scanid/capture")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        workScope.cancel()
        if (textRecognizerLazy.isInitialized()) textRecognizer.close()
        if (barcodeScannerLazy.isInitialized()) barcodeScanner.close()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "detectDocumentRect") {
            // No imported-image document detection on Android yet (ML Kit's
            // scanner is a live-camera flow, not a "find the doc in this
            // image" API). Null → the caller's crop UI opens with a default
            // rect the user drags (manual crop), same confirm step as iOS.
            result.success(null)
            return
        }
        if (call.method != "recognizeText" && call.method != "recognizeBarcodes") {
            result.notImplemented()
            return
        }
        val bytes = call.argument<ByteArray>("image")
        // The full-image bitmap decode is 100-500 ms of synchronous work — off
        // the platform thread (ML Kit's own processing is already async; its
        // listeners fire back on main, so no extra hop is needed there).
        workScope.launch {
            val bitmap = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
            if (bitmap == null) {
                withContext(Dispatchers.Main) {
                    result.error("bad_image", "Could not decode image", null)
                }
                return@launch
            }
            val image = InputImage.fromBitmap(bitmap, 0)
            if (call.method == "recognizeText") {
                textRecognizer
                    .process(image)
                    .addOnSuccessListener { visionText ->
                        val w = bitmap.width.toDouble()
                        val h = bitmap.height.toDouble()
                        val lines = visionText.textBlocks
                            .flatMap { it.lines }
                            .map { line ->
                                val m = mutableMapOf<String, Any>(
                                    "text" to line.text,
                                    "confidence" to (line.confidence?.toDouble() ?: 1.0),
                                )
                                line.boundingBox?.let { b ->
                                    // Pixel Rect → normalized, top-left origin.
                                    m["box"] = mapOf(
                                        "left" to b.left / w,
                                        "top" to b.top / h,
                                        "width" to b.width() / w,
                                        "height" to b.height() / h,
                                    )
                                }
                                m
                            }
                        result.success(lines)
                    }
                    .addOnFailureListener { e ->
                        result.error("ocr_failed", e.message, null)
                    }
            } else {
                barcodeScanner
                    .process(image)
                    .addOnSuccessListener { barcodes ->
                        result.success(barcodes.mapNotNull { it.rawValue })
                    }
                    .addOnFailureListener { result.success(emptyList<String>()) }
            }
        }
    }
}
