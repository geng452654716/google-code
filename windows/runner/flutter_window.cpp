#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <wtsapi32.h>

#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "screen_capture.h"
#include "secure_key_store.h"

namespace {

/// Ensures every successful OpenClipboard call is paired with CloseClipboard.
class ClipboardScope {
 public:
  ClipboardScope() : opened_(OpenClipboard(nullptr) != FALSE) {}
  ~ClipboardScope() {
    if (opened_) CloseClipboard();
  }

  bool opened() const { return opened_; }

 private:
  bool opened_;
};

/// Wraps a CF_DIB clipboard payload in a BMP file header for Dart decoding.
std::optional<std::vector<uint8_t>> ReadClipboardBitmap() {
  const UINT format = IsClipboardFormatAvailable(CF_DIBV5) ? CF_DIBV5 : CF_DIB;
  if (!IsClipboardFormatAvailable(format)) return std::nullopt;

  HANDLE handle = GetClipboardData(format);
  if (handle == nullptr) return std::nullopt;
  const SIZE_T dib_size = GlobalSize(handle);
  if (dib_size < sizeof(BITMAPINFOHEADER) ||
      dib_size >
          std::numeric_limits<uint32_t>::max() - sizeof(BITMAPFILEHEADER)) {
    return std::nullopt;
  }

  const auto* dib = static_cast<const uint8_t*>(GlobalLock(handle));
  if (dib == nullptr) return std::nullopt;
  const auto* info = reinterpret_cast<const BITMAPINFOHEADER*>(dib);
  if (info->biSize < sizeof(BITMAPINFOHEADER) || info->biSize > dib_size) {
    GlobalUnlock(handle);
    return std::nullopt;
  }

  uint64_t palette_entries = info->biClrUsed;
  if (palette_entries == 0 && info->biBitCount <= 8) {
    palette_entries = uint64_t{1} << info->biBitCount;
  }
  uint64_t mask_bytes = 0;
  if (info->biSize == sizeof(BITMAPINFOHEADER) &&
      info->biCompression == BI_BITFIELDS) {
    mask_bytes = 3 * sizeof(DWORD);
  }
#ifdef BI_ALPHABITFIELDS
  if (info->biSize == sizeof(BITMAPINFOHEADER) &&
      info->biCompression == BI_ALPHABITFIELDS) {
    mask_bytes = 4 * sizeof(DWORD);
  }
#endif

  const uint64_t pixel_offset = sizeof(BITMAPFILEHEADER) + info->biSize +
                                mask_bytes + palette_entries * sizeof(RGBQUAD);
  const uint64_t file_size = sizeof(BITMAPFILEHEADER) + dib_size;
  if (pixel_offset > file_size) {
    GlobalUnlock(handle);
    return std::nullopt;
  }

  BITMAPFILEHEADER file_header{};
  file_header.bfType = 0x4D42;
  file_header.bfSize = static_cast<DWORD>(file_size);
  file_header.bfOffBits = static_cast<DWORD>(pixel_offset);

  std::vector<uint8_t> bitmap(static_cast<size_t>(file_size));
  std::memcpy(bitmap.data(), &file_header, sizeof(file_header));
  std::memcpy(bitmap.data() + sizeof(file_header), dib, dib_size);
  GlobalUnlock(handle);
  return bitmap;
}

/// Registers the native clipboard-image method used by the Dart import layer.
void RegisterClipboardImportChannel(flutter::FlutterEngine* engine) {
  FlutterDesktopPluginRegistrarRef registrar_ref =
      engine->GetRegistrarForPlugin("ClipboardImport");
  auto* registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar_ref);
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "google_code/clipboard_import",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "readImage") {
      result->NotImplemented();
      return;
    }

    ClipboardScope clipboard;
    if (!clipboard.opened()) {
      result->Error("clipboard_unavailable",
                    "The Windows clipboard is currently unavailable.");
      return;
    }
    auto bitmap = ReadClipboardBitmap();
    if (!bitmap.has_value()) {
      result->Success();
      return;
    }
    result->Success(flutter::EncodableValue(std::move(bitmap.value())));
  });
}

/// Registers the native in-memory Windows region screenshot method.
void RegisterScreenCaptureChannel(flutter::FlutterEngine* engine, HWND owner) {
  FlutterDesktopPluginRegistrarRef registrar_ref =
      engine->GetRegistrarForPlugin("ScreenCapture");
  auto* registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar_ref);
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "google_code/screen_capture",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([owner](const auto& call, auto result) {
    if (call.method_name() == "openScreenRecordingSettings") {
      // GDI desktop capture does not require a Windows privacy permission page.
      result->Success();
      return;
    }
    if (call.method_name() != "captureRegion") {
      result->NotImplemented();
      return;
    }

    auto capture = screen_capture::CaptureRegion(owner);
    switch (capture.status) {
      case screen_capture::CaptureStatus::kSuccess:
        result->Success(flutter::EncodableValue(std::move(capture.bytes)));
        return;
      case screen_capture::CaptureStatus::kCancelled:
        result->Success();
        return;
      case screen_capture::CaptureStatus::kFailed:
        result->Error("capture_failed", capture.message);
        return;
    }
  });
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterClipboardImportChannel(flutter_controller_->engine());
  RegisterScreenCaptureChannel(flutter_controller_->engine(), GetHandle());
  RegisterSecureKeyStoreChannel(flutter_controller_->engine());
  RegisterSystemSessionEventChannel();
  wts_session_notifications_registered_ =
      WTSRegisterSessionNotification(GetHandle(), NOTIFY_FOR_THIS_SESSION) ==
      TRUE;
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() { this->Show(); });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (wts_session_notifications_registered_) {
    WTSUnRegisterSessionNotification(GetHandle());
    wts_session_notifications_registered_ = false;
  }
  system_session_event_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::RegisterSystemSessionEventChannel() {
  FlutterDesktopPluginRegistrarRef registrar_ref =
      flutter_controller_->engine()->GetRegistrarForPlugin(
          "SystemSessionEvents");
  auto* registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar_ref);
  system_session_event_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "google_code/system_session_events",
          &flutter::StandardMethodCodec::GetInstance());
}

void FlutterWindow::EmitSystemSessionEvent(const std::string& event) {
  if (!system_session_event_channel_) return;
  system_session_event_channel_->InvokeMethod(
      "systemSessionEvent",
      std::make_unique<flutter::EncodableValue>(event));
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Process security events before plugins can consume the window message.
  if (message == WM_WTSSESSION_CHANGE) {
    switch (wparam) {
      case WTS_SESSION_LOCK:
        EmitSystemSessionEvent("screenLocked");
        break;
      case WTS_CONSOLE_DISCONNECT:
      case WTS_REMOTE_DISCONNECT:
      case WTS_SESSION_LOGOFF:
      case WTS_SESSION_TERMINATE:
        EmitSystemSessionEvent("sessionDisconnected");
        break;
      default:
        break;
    }
  } else if (message == WM_POWERBROADCAST && wparam == PBT_APMSUSPEND) {
    EmitSystemSessionEvent("systemSleeping");
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
