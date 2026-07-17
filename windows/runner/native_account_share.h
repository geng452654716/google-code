#ifndef RUNNER_NATIVE_ACCOUNT_SHARE_H_
#define RUNNER_NATIVE_ACCOUNT_SHARE_H_

#include <flutter/flutter_engine.h>
#include <windows.h>

namespace native_account_share {

/// Registers the in-memory Windows system-share MethodChannel for [owner].
void RegisterChannel(flutter::FlutterEngine* engine, HWND owner);

}  // namespace native_account_share

#endif  // RUNNER_NATIVE_ACCOUNT_SHARE_H_
