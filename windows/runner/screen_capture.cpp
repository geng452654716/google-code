#include "screen_capture.h"

#include <dwmapi.h>
#include <windowsx.h>

#include <algorithm>
#include <cstring>
#include <limits>
#include <optional>
#include <utility>

namespace screen_capture {
namespace {

constexpr wchar_t kOverlayClassName[] = L"GoogleCodeScreenCaptureOverlay";
constexpr int kMinimumSelectionSize = 4;

/// Owns the top-down 32-bit desktop bitmap used by the overlay and crop step.
class CapturedDesktop {
 public:
  CapturedDesktop() = default;
  CapturedDesktop(const CapturedDesktop&) = delete;
  CapturedDesktop& operator=(const CapturedDesktop&) = delete;

  ~CapturedDesktop() {
    if (pixels_ != nullptr && width_ > 0 && height_ > 0) {
      const uint64_t byte_count = static_cast<uint64_t>(width_) * height_ * 4;
      if (byte_count <= std::numeric_limits<size_t>::max()) {
        SecureZeroMemory(pixels_, static_cast<size_t>(byte_count));
      }
    }
    if (memory_dc_ != nullptr && previous_bitmap_ != nullptr) {
      SelectObject(memory_dc_, previous_bitmap_);
    }
    if (bitmap_ != nullptr) DeleteObject(bitmap_);
    if (memory_dc_ != nullptr) DeleteDC(memory_dc_);
  }

  /// Captures the complete Windows virtual desktop into a top-down DIB.
  bool Capture() {
    origin_x_ = GetSystemMetrics(SM_XVIRTUALSCREEN);
    origin_y_ = GetSystemMetrics(SM_YVIRTUALSCREEN);
    width_ = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    height_ = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (width_ <= 0 || height_ <= 0) return false;

    HDC screen_dc = GetDC(nullptr);
    if (screen_dc == nullptr) return false;
    memory_dc_ = CreateCompatibleDC(screen_dc);
    if (memory_dc_ == nullptr) {
      ReleaseDC(nullptr, screen_dc);
      return false;
    }

    BITMAPINFO bitmap_info{};
    bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bitmap_info.bmiHeader.biWidth = width_;
    bitmap_info.bmiHeader.biHeight = -height_;
    bitmap_info.bmiHeader.biPlanes = 1;
    bitmap_info.bmiHeader.biBitCount = 32;
    bitmap_info.bmiHeader.biCompression = BI_RGB;

    bitmap_ = CreateDIBSection(screen_dc, &bitmap_info, DIB_RGB_COLORS,
                               &pixels_, nullptr, 0);
    if (bitmap_ == nullptr || pixels_ == nullptr) {
      ReleaseDC(nullptr, screen_dc);
      return false;
    }
    previous_bitmap_ = SelectObject(memory_dc_, bitmap_);
    if (previous_bitmap_ == nullptr || previous_bitmap_ == HGDI_ERROR) {
      previous_bitmap_ = nullptr;
      ReleaseDC(nullptr, screen_dc);
      return false;
    }

    const BOOL copied = BitBlt(memory_dc_, 0, 0, width_, height_, screen_dc,
                               origin_x_, origin_y_, SRCCOPY | CAPTUREBLT);
    ReleaseDC(nullptr, screen_dc);
    return copied == TRUE;
  }

  /// Encodes a selected client-coordinate rectangle as an in-memory BMP file.
  std::optional<std::vector<uint8_t>> EncodeCrop(RECT selection) const {
    selection.left = std::clamp(selection.left, 0L, static_cast<LONG>(width_));
    selection.right =
        std::clamp(selection.right, 0L, static_cast<LONG>(width_));
    selection.top = std::clamp(selection.top, 0L, static_cast<LONG>(height_));
    selection.bottom =
        std::clamp(selection.bottom, 0L, static_cast<LONG>(height_));

    const int crop_width = selection.right - selection.left;
    const int crop_height = selection.bottom - selection.top;
    if (crop_width < kMinimumSelectionSize ||
        crop_height < kMinimumSelectionSize || pixels_ == nullptr) {
      return std::nullopt;
    }

    const uint64_t row_bytes = static_cast<uint64_t>(crop_width) * 4;
    const uint64_t pixel_bytes = row_bytes * crop_height;
    const uint64_t header_bytes =
        sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
    const uint64_t file_bytes = header_bytes + pixel_bytes;
    if (file_bytes > std::numeric_limits<uint32_t>::max() ||
        file_bytes > std::numeric_limits<size_t>::max()) {
      return std::nullopt;
    }

    BITMAPFILEHEADER file_header{};
    file_header.bfType = 0x4D42;
    file_header.bfSize = static_cast<DWORD>(file_bytes);
    file_header.bfOffBits = static_cast<DWORD>(header_bytes);

    BITMAPINFOHEADER info_header{};
    info_header.biSize = sizeof(BITMAPINFOHEADER);
    info_header.biWidth = crop_width;
    info_header.biHeight = -crop_height;
    info_header.biPlanes = 1;
    info_header.biBitCount = 32;
    info_header.biCompression = BI_RGB;
    info_header.biSizeImage = static_cast<DWORD>(pixel_bytes);

    std::vector<uint8_t> bitmap(static_cast<size_t>(file_bytes));
    std::memcpy(bitmap.data(), &file_header, sizeof(file_header));
    std::memcpy(bitmap.data() + sizeof(file_header), &info_header,
                sizeof(info_header));

    const auto* source = static_cast<const uint8_t*>(pixels_);
    auto* destination = bitmap.data() + header_bytes;
    const size_t source_stride = static_cast<size_t>(width_) * 4;
    for (int row = 0; row < crop_height; ++row) {
      const size_t source_offset =
          static_cast<size_t>(selection.top + row) * source_stride +
          static_cast<size_t>(selection.left) * 4;
      std::memcpy(destination + static_cast<size_t>(row) * row_bytes,
                  source + source_offset, static_cast<size_t>(row_bytes));
    }
    return bitmap;
  }

  HDC memory_dc() const { return memory_dc_; }
  int origin_x() const { return origin_x_; }
  int origin_y() const { return origin_y_; }
  int width() const { return width_; }
  int height() const { return height_; }

 private:
  int origin_x_ = 0;
  int origin_y_ = 0;
  int width_ = 0;
  int height_ = 0;
  HDC memory_dc_ = nullptr;
  HBITMAP bitmap_ = nullptr;
  HGDIOBJ previous_bitmap_ = nullptr;
  void* pixels_ = nullptr;
};

/// Restores the Flutter window even when capture setup or selection fails.
class OwnerWindowRestorer {
 public:
  explicit OwnerWindowRestorer(HWND owner) : owner_(owner) {
    if (owner_ == nullptr || !IsWindow(owner_)) return;
    was_visible_ = IsWindowVisible(owner_) == TRUE;
    placement_.length = sizeof(WINDOWPLACEMENT);
    has_placement_ = GetWindowPlacement(owner_, &placement_) == TRUE;
    if (was_visible_) {
      ShowWindow(owner_, SW_HIDE);
      DwmFlush();
    }
  }

  ~OwnerWindowRestorer() {
    if (owner_ == nullptr || !IsWindow(owner_) || !was_visible_) return;
    const int command = has_placement_ && placement_.showCmd == SW_SHOWMAXIMIZED
                            ? SW_SHOWMAXIMIZED
                            : SW_RESTORE;
    ShowWindow(owner_, command);
    SetForegroundWindow(owner_);
    SetActiveWindow(owner_);
  }

 private:
  HWND owner_ = nullptr;
  bool was_visible_ = false;
  bool has_placement_ = false;
  WINDOWPLACEMENT placement_{};
};

struct OverlayState {
  CapturedDesktop* desktop = nullptr;
  POINT start{};
  POINT current{};
  RECT selection{};
  bool selecting = false;
  bool completed = false;
  bool cancelled = true;
};

/// Returns a normalized, virtual-desktop-bounded selection rectangle.
RECT NormalizeSelection(const OverlayState& state) {
  RECT rect{
      std::min(state.start.x, state.current.x),
      std::min(state.start.y, state.current.y),
      std::max(state.start.x, state.current.x),
      std::max(state.start.y, state.current.y),
  };
  if (state.desktop != nullptr) {
    rect.left =
        std::clamp(rect.left, 0L, static_cast<LONG>(state.desktop->width()));
    rect.right =
        std::clamp(rect.right, 0L, static_cast<LONG>(state.desktop->width()));
    rect.top =
        std::clamp(rect.top, 0L, static_cast<LONG>(state.desktop->height()));
    rect.bottom =
        std::clamp(rect.bottom, 0L, static_cast<LONG>(state.desktop->height()));
  }
  return rect;
}

/// Applies a translucent black layer while leaving the selected area bright.
void DimSurface(HDC destination, int width, int height) {
  HDC shade_dc = CreateCompatibleDC(destination);
  if (shade_dc == nullptr) return;

  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = 1;
  info.bmiHeader.biHeight = -1;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* pixel = nullptr;
  HBITMAP shade_bitmap =
      CreateDIBSection(destination, &info, DIB_RGB_COLORS, &pixel, nullptr, 0);
  if (shade_bitmap == nullptr || pixel == nullptr) {
    if (shade_bitmap != nullptr) DeleteObject(shade_bitmap);
    DeleteDC(shade_dc);
    return;
  }

  *static_cast<uint32_t*>(pixel) = 0x00000000;
  HGDIOBJ previous = SelectObject(shade_dc, shade_bitmap);
  BLENDFUNCTION blend{AC_SRC_OVER, 0, 105, 0};
  AlphaBlend(destination, 0, 0, width, height, shade_dc, 0, 0, 1, 1, blend);
  SelectObject(shade_dc, previous);
  DeleteObject(shade_bitmap);
  DeleteDC(shade_dc);
}

/// Paints the frozen desktop, selection highlight, and concise instructions.
void PaintOverlay(HWND window, OverlayState* state) {
  PAINTSTRUCT paint{};
  HDC destination = BeginPaint(window, &paint);
  if (state == nullptr || state->desktop == nullptr) {
    EndPaint(window, &paint);
    return;
  }

  auto* desktop = state->desktop;
  BitBlt(destination, 0, 0, desktop->width(), desktop->height(),
         desktop->memory_dc(), 0, 0, SRCCOPY);
  DimSurface(destination, desktop->width(), desktop->height());

  if (state->selecting) {
    const RECT selection = NormalizeSelection(*state);
    const int width = selection.right - selection.left;
    const int height = selection.bottom - selection.top;
    if (width > 0 && height > 0) {
      BitBlt(destination, selection.left, selection.top, width, height,
             desktop->memory_dc(), selection.left, selection.top, SRCCOPY);
      HPEN pen = CreatePen(PS_SOLID, 2, RGB(66, 133, 244));
      HGDIOBJ previous_pen = SelectObject(destination, pen);
      HGDIOBJ previous_brush =
          SelectObject(destination, GetStockObject(NULL_BRUSH));
      Rectangle(destination, selection.left, selection.top, selection.right,
                selection.bottom);
      SelectObject(destination, previous_brush);
      SelectObject(destination, previous_pen);
      DeleteObject(pen);
    }
  }

  RECT instruction{24, 24, 520, 66};
  HBRUSH background = CreateSolidBrush(RGB(24, 24, 24));
  FillRect(destination, &instruction, background);
  DeleteObject(background);
  SetBkMode(destination, TRANSPARENT);
  SetTextColor(destination, RGB(255, 255, 255));
  DrawTextW(destination,
            L"\u62D6\u52A8\u9009\u62E9\u4E8C\u7EF4\u7801\u533A\u57DF  -  Esc "
            L"\u6216\u53F3\u952E\u53D6\u6D88",
            -1, &instruction, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  EndPaint(window, &paint);
}

LRESULT CALLBACK OverlayWindowProc(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam) {
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<const CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    return TRUE;
  }

  auto* state =
      reinterpret_cast<OverlayState*>(GetWindowLongPtr(window, GWLP_USERDATA));
  switch (message) {
    case WM_ERASEBKGND:
      return 1;
    case WM_SETCURSOR:
      SetCursor(LoadCursor(nullptr, IDC_CROSS));
      return TRUE;
    case WM_LBUTTONDOWN:
      if (state != nullptr) {
        SetFocus(window);
        SetCapture(window);
        state->selecting = true;
        state->start = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        state->current = state->start;
        InvalidateRect(window, nullptr, FALSE);
      }
      return 0;
    case WM_MOUSEMOVE:
      if (state != nullptr && state->selecting && (wparam & MK_LBUTTON) != 0) {
        state->current = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        InvalidateRect(window, nullptr, FALSE);
      }
      return 0;
    case WM_LBUTTONUP:
      if (state != nullptr && state->selecting) {
        state->current = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        state->selecting = false;
        if (GetCapture() == window) ReleaseCapture();
        state->selection = NormalizeSelection(*state);
        const int width = state->selection.right - state->selection.left;
        const int height = state->selection.bottom - state->selection.top;
        if (width >= kMinimumSelectionSize && height >= kMinimumSelectionSize) {
          state->completed = true;
          state->cancelled = false;
          DestroyWindow(window);
        } else {
          InvalidateRect(window, nullptr, FALSE);
        }
      }
      return 0;
    case WM_RBUTTONDOWN:
    case WM_CLOSE:
      if (state != nullptr) {
        state->completed = true;
        state->cancelled = true;
      }
      DestroyWindow(window);
      return 0;
    case WM_KEYDOWN:
      if (wparam == VK_ESCAPE) {
        if (state != nullptr) {
          state->completed = true;
          state->cancelled = true;
        }
        DestroyWindow(window);
        return 0;
      }
      break;
    case WM_PAINT:
      PaintOverlay(window, state);
      return 0;
  }
  return DefWindowProc(window, message, wparam, lparam);
}

/// Registers the process-local overlay window class once.
bool EnsureOverlayWindowClass(HINSTANCE instance) {
  WNDCLASSEX window_class{};
  window_class.cbSize = sizeof(WNDCLASSEX);
  window_class.style = CS_HREDRAW | CS_VREDRAW;
  window_class.lpfnWndProc = OverlayWindowProc;
  window_class.hInstance = instance;
  window_class.hCursor = LoadCursor(nullptr, IDC_CROSS);
  window_class.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
  window_class.lpszClassName = kOverlayClassName;
  if (RegisterClassEx(&window_class) != 0) return true;
  return GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

/// Runs a nested message loop until the overlay confirms or cancels selection.
bool SelectRegion(CapturedDesktop* desktop, RECT* selection, bool* cancelled) {
  if (desktop == nullptr || selection == nullptr || cancelled == nullptr) {
    return false;
  }
  HINSTANCE instance = GetModuleHandle(nullptr);
  if (!EnsureOverlayWindowClass(instance)) return false;

  OverlayState state{};
  state.desktop = desktop;
  HWND overlay = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW, kOverlayClassName, L"", WS_POPUP,
      desktop->origin_x(), desktop->origin_y(), desktop->width(),
      desktop->height(), nullptr, nullptr, instance, &state);
  if (overlay == nullptr) return false;

  ShowWindow(overlay, SW_SHOW);
  UpdateWindow(overlay);
  SetForegroundWindow(overlay);
  SetFocus(overlay);

  MSG message{};
  while (IsWindow(overlay)) {
    const BOOL message_result = GetMessage(&message, nullptr, 0, 0);
    if (message_result == 0) {
      if (IsWindow(overlay)) DestroyWindow(overlay);
      PostQuitMessage(static_cast<int>(message.wParam));
      return false;
    }
    if (message_result == -1) {
      if (IsWindow(overlay)) DestroyWindow(overlay);
      return false;
    }
    TranslateMessage(&message);
    DispatchMessage(&message);
  }

  *selection = state.selection;
  *cancelled = state.cancelled || !state.completed;
  return true;
}

}  // namespace

CaptureResult CaptureRegion(HWND owner) {
  if (owner == nullptr || !IsWindow(owner)) {
    return {CaptureStatus::kFailed, {}, "Application window is unavailable."};
  }

  OwnerWindowRestorer restore_owner(owner);
  CapturedDesktop desktop;
  if (!desktop.Capture()) {
    return {
        CaptureStatus::kFailed, {}, "Unable to capture the Windows desktop."};
  }

  RECT selection{};
  bool cancelled = true;
  if (!SelectRegion(&desktop, &selection, &cancelled)) {
    return {CaptureStatus::kFailed, {}, "Unable to open the region selector."};
  }
  if (cancelled) return {CaptureStatus::kCancelled, {}, {}};

  auto bitmap = desktop.EncodeCrop(selection);
  if (!bitmap.has_value()) {
    return {CaptureStatus::kFailed,
            {},
            "The selected region could not be encoded."};
  }
  return {CaptureStatus::kSuccess, std::move(bitmap.value()), {}};
}

}  // namespace screen_capture
