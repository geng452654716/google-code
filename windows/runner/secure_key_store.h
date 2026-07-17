#ifndef RUNNER_SECURE_KEY_STORE_H_
#define RUNNER_SECURE_KEY_STORE_H_

#include <flutter/flutter_engine.h>

/// Registers the Windows Credential Manager channel for quick-unlock material.
void RegisterSecureKeyStoreChannel(flutter::FlutterEngine* engine);

#endif  // RUNNER_SECURE_KEY_STORE_H_
