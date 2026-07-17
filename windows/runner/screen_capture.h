#ifndef RUNNER_SCREEN_CAPTURE_H_
#define RUNNER_SCREEN_CAPTURE_H_

#include <windows.h>

#include <cstdint>
#include <string>
#include <vector>

namespace screen_capture {

/// Outcome of one user-initiated region screenshot operation.
enum class CaptureStatus { kSuccess, kCancelled, kFailed };

/// Encoded BMP bytes or a safe native diagnostic for the platform channel.
struct CaptureResult {
  CaptureStatus status = CaptureStatus::kFailed;
  std::vector<uint8_t> bytes;
  std::string message;
};

/// Hides the owner, lets the user drag a region, and captures it in memory.
CaptureResult CaptureRegion(HWND owner);

}  // namespace screen_capture

#endif  // RUNNER_SCREEN_CAPTURE_H_
