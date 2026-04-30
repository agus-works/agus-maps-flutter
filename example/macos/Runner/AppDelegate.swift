import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    scheduleFlutterRunShutdownFallback()
    return .terminateNow
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    scheduleFlutterRunShutdownFallback()
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func scheduleFlutterRunShutdownFallback() {
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(500)) {
      Darwin._exit(EXIT_SUCCESS)
    }
  }
}
