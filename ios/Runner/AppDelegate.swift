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
    guard FileManager.default.fileExists(atPath: path) else {
      result(false)
      return
    }

    guard let image = UIImage(contentsOfFile: path) else {
      result(false)
      return
    }

    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      if status == .authorized || status == .limited {
        PHPhotoLibrary.shared().performChanges({
          PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
          DispatchQueue.main.async {
            if let error = error {
              print("[Pixora] Save to gallery error: \(error.localizedDescription)")
            }
            result(success)
          }
        }
      } else {
        DispatchQueue.main.async {
          result(false)
        }
      }
    }
  }
}
