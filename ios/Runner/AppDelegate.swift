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

    let fileExists = FileManager.default.fileExists(atPath: path)
    print("[Pixora-iOS] File exists: \(fileExists)")

    guard fileExists else {
      print("[Pixora-iOS] ERROR: File does not exist at path")
      result(FlutterError(code: "FILE_NOT_FOUND", message: "File not found: \(path)", details: nil))
      return
    }

    // Log file size
    if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
       let size = attrs[.size] as? Int {
      print("[Pixora-iOS] File size: \(size) bytes")
    }

    guard let image = UIImage(contentsOfFile: path) else {
      print("[Pixora-iOS] ERROR: Could not load image from file")
      result(FlutterError(code: "INVALID_IMAGE", message: "Cannot load image from: \(path)", details: nil))
      return
    }

    print("[Pixora-iOS] Image loaded OK: \(image.size.width)x\(image.size.height)")

    if #available(iOS 14, *) {
      let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      print("[Pixora-iOS] Current photo auth status: \(currentStatus.rawValue)")

      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        print("[Pixora-iOS] Auth status after request: \(status.rawValue) (3=authorized, 4=limited)")
        if status == .authorized || status == .limited {
          PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
          }) { success, error in
            print("[Pixora-iOS] performChanges result: success=\(success), error=\(String(describing: error))")
            DispatchQueue.main.async { result(success) }
          }
        } else {
          print("[Pixora-iOS] Photo permission DENIED (status: \(status.rawValue))")
          DispatchQueue.main.async { result(false) }
        }
      }
    } else {
      PHPhotoLibrary.requestAuthorization { status in
        print("[Pixora-iOS] Auth status (legacy): \(status.rawValue)")
        if status == .authorized {
          PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
          }) { success, error in
            print("[Pixora-iOS] performChanges result: success=\(success), error=\(String(describing: error))")
            DispatchQueue.main.async { result(success) }
          }
        } else {
          DispatchQueue.main.async { result(false) }
        }
      }
    }
  }
}
