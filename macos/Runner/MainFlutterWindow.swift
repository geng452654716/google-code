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

/// Retains an in-memory NSSharingServicePicker until the user chooses or cancels.
private final class NativeAccountShareCoordinator: NSObject, NSSharingServicePickerDelegate {
  private weak var window: NSWindow?
  private var picker: NSSharingServicePicker?
  private var retainedItems: [Any] = []

  init(window: NSWindow) {
    self.window = window
  }

  /// Presents text and QR image bytes without creating a plaintext temporary file.
  func present(text: String, qrPng: Data) -> Bool {
    guard picker == nil, let window, let contentView = window.contentView,
      let image = NSImage(data: qrPng)
    else {
      return false
    }

    retainedItems = [text, image]
    let picker = NSSharingServicePicker(items: retainedItems)
    picker.delegate = self
    self.picker = picker

    let anchor = NSRect(
      x: contentView.bounds.midX,
      y: contentView.bounds.maxY - 1,
      width: 1,
      height: 1)
    picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
    return true
  }

  /// Releases the only application-owned references after selection or cancel.
  func sharingServicePicker(
    _ sharingServicePicker: NSSharingServicePicker,
    didChoose service: NSSharingService?
  ) {
    picker = nil
    retainedItems.removeAll(keepingCapacity: false)
  }
}

class MainFlutterWindow: NSWindow {
  private var systemSessionEventEmitter: SystemSessionEventEmitter?
  private var nativeAccountShareCoordinator: NativeAccountShareCoordinator?
  private var imageImportPanel: NSOpenPanel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerClipboardImportChannel(with: flutterViewController)
    registerImageImportPickerChannel(with: flutterViewController)
    registerScreenCaptureChannel(with: flutterViewController)
    registerSecureKeyStoreChannel(with: flutterViewController)
    registerNativeAccountShareChannel(with: flutterViewController)
    let sessionRegistrar = flutterViewController.registrar(forPlugin: "SystemSessionEvents")
    systemSessionEventEmitter = SystemSessionEventEmitter(
      messenger: sessionRegistrar.messenger)

    super.awakeFromNib()
  }

  /// Uses an app-activated native panel so the image chooser cannot open behind Flutter.
  private func registerImageImportPickerChannel(with controller: FlutterViewController) {
    let registrar = controller.registrar(forPlugin: "ImageImportPicker")
    let channel = FlutterMethodChannel(
      name: "google_code/image_import_picker",
      binaryMessenger: registrar.messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickQrImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self else {
        result(
          FlutterError(
            code: "image_picker_unavailable",
            message: "The image picker is unavailable.",
            details: nil))
        return
      }
      self.presentImageImportPanel(result: result)
    }
  }

  private func presentImageImportPanel(result: @escaping FlutterResult) {
    guard imageImportPanel == nil else {
      result(
        FlutterError(
          code: "image_picker_busy",
          message: "An image picker is already open.",
          details: nil))
      return
    }

    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)

    let panel = NSOpenPanel()
    panel.title = "选择二维码图片"
    panel.prompt = "选择图片"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true
    panel.allowedFileTypes = ["png", "jpg", "jpeg", "webp", "bmp", "gif", "tif", "tiff"]
    imageImportPanel = panel

    // The Flutter add-account dialog has just closed. Delaying one run-loop turn
    // prevents AppKit from attaching the open panel beneath its dismissal animation.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak panel] in
      guard let self, let panel else {
        result(
          FlutterError(
            code: "image_picker_unavailable",
            message: "The image picker is unavailable.",
            details: nil))
        return
      }
      NSApp.activate(ignoringOtherApps: true)
      self.makeKeyAndOrderFront(nil)
      panel.beginSheetModal(for: self) { [weak self] response in
        defer { self?.imageImportPanel = nil }
        guard response == .OK, let url = panel.url else {
          result(nil)
          return
        }
        do {
          let data = try Data(contentsOf: url, options: .mappedIfSafe)
          result([
            "name": url.lastPathComponent,
            "bytes": FlutterStandardTypedData(bytes: data),
          ])
        } catch {
          result(
            FlutterError(
              code: "image_read_failed",
              message: "Unable to read the selected image.",
              details: nil))
        }
      }
    }
  }

  /// Exposes the native macOS share picker for one ephemeral account package.
  private func registerNativeAccountShareChannel(with controller: FlutterViewController) {
    let registrar = controller.registrar(forPlugin: "NativeAccountShare")
    let channel = FlutterMethodChannel(
      name: "google_code/native_account_share",
      binaryMessenger: registrar.messenger)
    let coordinator = NativeAccountShareCoordinator(window: self)
    nativeAccountShareCoordinator = coordinator

    channel.setMethodCallHandler { call, result in
      guard call.method == "shareAccount" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let title = arguments["title"] as? String,
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        let text = arguments["text"] as? String,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        let typedData = arguments["qrPng"] as? FlutterStandardTypedData,
        !typedData.data.isEmpty,
        typedData.data.count <= 5 * 1024 * 1024
      else {
        result(
          FlutterError(
            code: "invalid_share_payload",
            message: "The native share payload is missing or invalid.",
            details: nil))
        return
      }
      guard coordinator.present(text: text, qrPng: typedData.data) else {
        result(
          FlutterError(
            code: "share_unavailable",
            message: "The macOS share picker could not be presented.",
            details: nil))
        return
      }

      // Return immediately so Dart can conceal its copy while the picker is open.
      result("presented")
    }
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
      case "restartApplication":
        self.restartApplication(result: result)
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
    // Keep the only application window alive and visible in the Dock. Calling
    // orderOut made the app appear to have crashed while macOS showed its
    // crosshair selector. Minimizing gives the user an explicit lifecycle cue
    // and lets us reliably restore the same window after success or cancel.
    miniaturize(nil)

    // Allow the minimize animation to finish so the application window is not
    // accidentally included in the selected screen region.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      self?.runInteractiveScreenCapture(
        pasteboardChangeCount: pasteboardChangeCount,
        result: result)
    }
  }

  /// Executes macOS screencapture away from the Flutter platform thread.
  private func runInteractiveScreenCapture(
    pasteboardChangeCount: Int,
    result: @escaping FlutterResult
  ) {
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
    if isMiniaturized {
      deminiaturize(nil)
    }
    makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Opens Screen Recording settings across current and legacy macOS releases.
  ///
  /// Apple has used more than one System Settings extension identifier. Try the
  /// current Privacy & Security extension first, retain the legacy preference
  /// pane URL for older systems, and finally open System Settings itself so the
  /// user is never left with a button that appears to do nothing.
  private func openScreenRecordingSettings(result: @escaping FlutterResult) {
    let destinations: [(String, String)] = [
      (
        "screenRecording",
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
      ),
      (
        "screenRecordingLegacy",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
      ),
    ]

    for (destination, rawURL) in destinations {
      guard let url = URL(string: rawURL) else { continue }
      if NSWorkspace.shared.open(url) {
        result(destination)
        return
      }
    }

    if let settingsURL = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: "com.apple.systempreferences"
    ), NSWorkspace.shared.open(settingsURL) {
      result("systemSettings")
      return
    }

    let fallbackURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
    if FileManager.default.fileExists(atPath: fallbackURL.path),
      NSWorkspace.shared.open(fallbackURL)
    {
      result("systemSettings")
      return
    }

    result(
      FlutterError(
        code: "settings_failed", message: "Unable to open system settings.", details: nil))
  }

  /// Restarts the same installed bundle so a newly granted TCC permission is reloaded.
  private func restartApplication(result: @escaping FlutterResult) {
    let applicationURL = Bundle.main.bundleURL
    let relauncher = Process()
    relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
    relauncher.arguments = [
      "-c",
      "sleep 1; /usr/bin/open -n \"$1\"",
      "google-code-relauncher",
      applicationURL.path,
    ]

    do {
      try relauncher.run()
    } catch {
      result(
        FlutterError(
          code: "restart_failed", message: "Unable to restart application.", details: nil))
      return
    }

    result(nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      NSApp.terminate(nil)
    }
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
