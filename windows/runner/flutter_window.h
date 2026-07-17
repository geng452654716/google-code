#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Creates the channel that forwards OS session security events to Dart.
  void RegisterSystemSessionEventChannel();

  // Emits one normalized event name through the system-session channel.
  void EmitSystemSessionEvent(const std::string& event);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Kept alive for the full window lifetime so native events can reach Dart.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      system_session_event_channel_;

  // Tracks whether WTSUnRegisterSessionNotification is required on teardown.
  bool wts_session_notifications_registered_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
