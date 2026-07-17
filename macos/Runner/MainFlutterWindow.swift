import Cocoa
import CoreGraphics
import FlutterMacOS
import Security

/// Emits only security-sensitive operating-system session transitions to Dart.
private final class SystemSessionEventEmitter {
  private static let channelName = "google_code/system_session_events"
  private static let eventMethod = "systemSessionEvent"

  private let channel: FlutterMethodChannel
  private var workspaceObservers: [NSObjectProtocol] = []
  private var distributedObservers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger)
    registerObservers()
  }

  deinit {
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    for observer in workspaceObservers {
      workspaceCenter.removeObserver(observer)
    }
    let distributedCenter = DistributedNotificationCenter.default()
    for observer in distributedObservers {
      distributedCenter.removeObserver(observer)
    }
  }

  /// Registers lock, inactive-session, system-sleep, and display-sleep events.
  private func registerObservers() {
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    workspaceObservers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.willSleepNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.emit("systemSleeping")
      })
    workspaceObservers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.screensDidSleepNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.emit("systemSleeping")
      })
    workspaceObservers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.sessionDidResignActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.emit("sessionDisconnected")
      })

    let distributedCenter = DistributedNotificationCenter.default()
    distributedObservers.append(
      distributedCenter.addObserver(
        forName: Notification.Name("com.apple.screenIsLocked"),
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.emit("screenLocked")
      })
  }

  /// Delivers native events on the main thread used by Flutter's messenger.
  private func emit(_ event: String) {
    if Thread.isMainThread {
      channel.invokeMethod(Self.eventMethod, arguments: event)
      return
    }
    DispatchQueue.main.async { [weak self] in
      self?.channel.invokeMethod(Self.eventMethod, arguments: event)
    }
  }
}

class MainFlutterWindow: NSWindow {
  private var systemSessionEventEmitter: SystemSessionEventEmitter?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerClipboardImportChannel(with: flutterViewController)
    registerScreenCaptureChannel(with: flutterViewController)
    registerSecureKeyStoreChannel(with: flutterViewController)
    let sessionRegistrar = flutterViewController.registrar(forPlugin: "SystemSessionEvents")
    systemSessionEventEmitter = SystemSessionEventEmitter(
      messenger: sessionRegistrar.messenger)

    super.awakeFromNib()
  }

  /// Exposes clipboard image bytes without writing sensitive data to disk.
  private func registerClipboardImportChannel(with controller: FlutterViewController) {
    let registrar = controller.registrar(forPlugin: "ClipboardImport")
    let channel = FlutterMethodChannel(
      name: "google_code/clipboard_import",
      binaryMessenger: registrar.messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "readImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let data = self?.clipboardImageData() else {
        result(nil)
        return
      }
      result(FlutterStandardTypedData(bytes: data))
    }
  }

  /// Exposes a Keychain-backed store for the device-only quick-unlock DEK.
  private func registerSecureKeyStoreChannel(with controller: FlutterViewController) {
    let registrar = controller.registrar(forPlugin: "SecureKeyStore")
    let channel = FlutterMethodChannel(
      name: "google_code/secure_key_store",
      binaryMessenger: registrar.messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "secure_store_unavailable",
            message: "Application window is unavailable.",
            details: nil))
        return
      }
      switch call.method {
      case "contains":
        result(self.containsQuickUnlockKey())
      case "read":
        self.readQuickUnlockKey(result: result)
      case "write":
        guard let typedData = call.arguments as? FlutterStandardTypedData,
          typedData.data.count == 32
        else {
          result(
            FlutterError(
              code: "invalid_key", message: "Quick unlock key is invalid.", details: nil))
          return
        }
        self.writeQuickUnlockKey(typedData.data, result: result)
      case "delete":
        self.deleteQuickUnlockKey(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Returns the fixed Keychain identity used only by this application.
  private var quickUnlockKeychainQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.gengyujian.google-code.quick-unlock",
      kSecAttrAccount as String: "vault-dek-v1",
    ]
  }

  /// Checks for a quick-unlock key without returning its bytes.
  private func containsQuickUnlockKey() -> Bool {
    var query = quickUnlockKeychainQuery
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnData as String] = false
    return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
  }

  /// Reads the protected DEK directly into the Flutter binary response.
  private func readQuickUnlockKey(result: FlutterResult) {
    var query = quickUnlockKeychainQuery
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnData as String] = true
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      result(nil)
      return
    }
    guard status == errSecSuccess, let data = item as? Data, data.count == 32 else {
      result(
        FlutterError(
          code: "secure_store_read_failed",
          message: "Unable to read quick unlock material.",
          details: nil))
      return
    }
    result(FlutterStandardTypedData(bytes: data))
  }

  /// Adds or atomically updates the device-only Keychain item.
  private func writeQuickUnlockKey(_ data: Data, result: FlutterResult) {
    var query = quickUnlockKeychainQuery
    let updateStatus = SecItemUpdate(
      query as CFDictionary,
      [kSecValueData as String: data] as CFDictionary)
    if updateStatus == errSecSuccess {
      result(nil)
      return
    }
    guard updateStatus == errSecItemNotFound else {
      result(
        FlutterError(
          code: "secure_store_write_failed",
          message: "Unable to update quick unlock material.",
          details: nil))
      return
    }
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let addStatus = SecItemAdd(query as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      result(
        FlutterError(
          code: "secure_store_write_failed",
          message: "Unable to save quick unlock material.",
          details: nil))
      return
    }
    result(nil)
  }

  /// Deletes only this application's quick-unlock item from Keychain.
  private func deleteQuickUnlockKey(result: FlutterResult) {
    let status = SecItemDelete(quickUnlockKeychainQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      result(
        FlutterError(
          code: "secure_store_delete_failed",
          message: "Unable to delete quick unlock material.",
          details: nil))
      return
    }
    result(nil)
  }

  /// Exposes interactive region capture and the related privacy settings page.
  private func registerScreenCaptureChannel(with controller: FlutterViewController) {
    let registrar = controller.registrar(forPlugin: "ScreenCapture")
    let channel = FlutterMethodChannel(
      name: "google_code/screen_capture",
      binaryMessenger: registrar.messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "capture_failed", message: "Application window is unavailable.", details: nil))
        return
      }
      switch call.method {
      case "captureRegion":
        self.captureRegion(result: result)
      case "openScreenRecordingSettings":
        self.openScreenRecordingSettings(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Runs the system region selector and returns the screenshot from memory.
  private func captureRegion(result: @escaping FlutterResult) {
    guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
      result(
        FlutterError(
          code: "permission_denied",
          message: "Screen recording permission is required.",
          details: nil))
      return
    }

    let pasteboardChangeCount = NSPasteboard.general.changeCount
    orderOut(nil)

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let process = Process()
      let errorPipe = Pipe()
      process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      process.arguments = ["-i", "-s", "-c", "-x"]
      process.standardError = errorPipe

      do {
        try process.run()
        process.waitUntilExit()
      } catch {
        DispatchQueue.main.async {
          self?.restoreAfterScreenCapture()
          result(
            FlutterError(
              code: "capture_failed", message: "Unable to start screen capture.", details: nil))
        }
        return
      }

      let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
      DispatchQueue.main.async {
        guard let self else {
          result(
            FlutterError(
              code: "capture_failed", message: "Application window is unavailable.", details: nil))
          return
        }
        self.restoreAfterScreenCapture()

        // Escape leaves the pasteboard untouched and normally emits no error.
        guard NSPasteboard.general.changeCount != pasteboardChangeCount else {
          if process.terminationStatus != 0, !errorOutput.isEmpty {
            result(
              FlutterError(
                code: "capture_failed", message: "Screen capture did not complete.", details: nil))
          } else {
            result(nil)
          }
          return
        }
        guard process.terminationStatus == 0, let data = self.clipboardImageData() else {
          result(
            FlutterError(
              code: "capture_failed", message: "No screenshot image was produced.", details: nil))
          return
        }
        result(FlutterStandardTypedData(bytes: data))
      }
    }
  }

  /// Restores focus after the system screenshot selector exits or is cancelled.
  private func restoreAfterScreenCapture() {
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Opens the macOS Privacy & Security screen-recording settings page.
  private func openScreenRecordingSettings(result: @escaping FlutterResult) {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
      NSWorkspace.shared.open(url)
    else {
      result(
        FlutterError(
          code: "settings_failed", message: "Unable to open system settings.", details: nil))
      return
    }
    result(nil)
  }

  /// Reads PNG/TIFF image data currently stored on the system pasteboard.
  private func clipboardImageData() -> Data? {
    let pasteboard = NSPasteboard.general
    for type in [NSPasteboard.PasteboardType.png, .tiff] {
      if let data = pasteboard.data(forType: type), !data.isEmpty {
        return data
      }
    }
    if let image = NSImage(pasteboard: pasteboard),
      let data = image.tiffRepresentation,
      !data.isEmpty
    {
      return data
    }
    return nil
  }
}
