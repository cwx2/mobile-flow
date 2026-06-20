import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Background task identifier for extending execution time.
  /// Allows the Dart isolate (heartbeat, WebSocket) to run briefly
  /// after the app enters background, covering quick app-switches.
  private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    // Request extra execution time from iOS when entering background.
    // This typically grants ~30 seconds of continued execution, which
    // is enough to maintain the WebSocket connection during brief
    // app switches (checking messages, quick photo, etc.).
    backgroundTaskID = application.beginBackgroundTask(withName: "MobileFlowKeepAlive") {
      // Expiration handler: system is about to suspend us.
      // Clean up the task so iOS doesn't penalize us.
      application.endBackgroundTask(self.backgroundTaskID)
      self.backgroundTaskID = .invalid
    }
    super.applicationDidEnterBackground(application)
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    // End the background task since we're back in foreground.
    if backgroundTaskID != .invalid {
      application.endBackgroundTask(backgroundTaskID)
      backgroundTaskID = .invalid
    }
    super.applicationWillEnterForeground(application)
  }
}
