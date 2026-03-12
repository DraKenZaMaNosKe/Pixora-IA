import UIKit
import Flutter
import Photos

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.orbix.pixora/wallpaper", binaryMessenger: controller.binaryMessenger)

    channel.setMethodCallHandler { (call, result) in
      if call.method == "saveToGallery" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARG", message: "Path is required", details: nil))
          return
        }
        self.saveToGallery(path: path, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func saveToGallery(path: String, result: @escaping FlutterResult) {
    print("[Pixora-iOS] saveToGallery called with path: \(path)")

    guard FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "FILE_NOT_FOUND", message: "File not found: \(path)", details: nil))
      return
    }

    guard let image = UIImage(contentsOfFile: path) else {
      result(FlutterError(code: "INVALID_IMAGE", message: "Cannot load image from: \(path)", details: nil))
      return
    }

    print("[Pixora-iOS] Image loaded: \(image.size.width)x\(image.size.height)")

    // Convert to JPEG data to ensure compatibility (WebP not always supported by Photos)
    guard let jpegData = image.jpegData(compressionQuality: 0.95) else {
      result(FlutterError(code: "CONVERT_FAIL", message: "Failed to convert image to JPEG", details: nil))
      return
    }

    print("[Pixora-iOS] Converted to JPEG: \(jpegData.count) bytes")

    // Write JPEG to temp file
    let tempPath = NSTemporaryDirectory() + "pixora_save.jpg"
    let tempUrl = URL(fileURLWithPath: tempPath)
    do {
      try jpegData.write(to: tempUrl)
    } catch {
      result(FlutterError(code: "WRITE_FAIL", message: "Failed to write temp JPEG: \(error)", details: nil))
      return
    }

    let saveBlock: () -> Void = {
      PHPhotoLibrary.shared().performChanges({
        PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: tempUrl, options: nil)
      }) { success, error in
        // Clean up temp file
        try? FileManager.default.removeItem(at: tempUrl)
        print("[Pixora-iOS] Save result: success=\(success), error=\(String(describing: error))")
        DispatchQueue.main.async {
          if success {
            result(true)
          } else {
            result(FlutterError(code: "SAVE_FAIL", message: "Photos save failed: \(error?.localizedDescription ?? "unknown")", details: nil))
          }
        }
      }
    }

    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        if status == .authorized || status == .limited {
          saveBlock()
        } else {
          DispatchQueue.main.async {
            result(FlutterError(code: "PERMISSION_DENIED", message: "Photo library access denied (status: \(status.rawValue))", details: nil))
          }
        }
      }
    } else {
      PHPhotoLibrary.requestAuthorization { status in
        if status == .authorized {
          saveBlock()
        } else {
          DispatchQueue.main.async {
            result(FlutterError(code: "PERMISSION_DENIED", message: "Photo library access denied", details: nil))
          }
        }
      }
    }
  }
}
