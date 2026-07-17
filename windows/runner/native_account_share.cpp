#include "native_account_share.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <utility>
#include <vector>

#include <shcore.h>
#include <shlwapi.h>
#include <shobjidl_core.h>
#include <windows.applicationmodel.datatransfer.h>
#include <windows.storage.streams.h>

#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.ApplicationModel.DataTransfer.h>
#include <winrt/Windows.Storage.Streams.h>

namespace native_account_share {
namespace {

using winrt::Windows::ApplicationModel::DataTransfer::DataRequestedEventArgs;
using winrt::Windows::ApplicationModel::DataTransfer::DataTransferManager;
using winrt::Windows::Storage::Streams::IRandomAccessStream;
using winrt::Windows::Storage::Streams::RandomAccessStreamReference;

constexpr size_t kMaximumQrBytes = 5 * 1024 * 1024;

/// Retains the sensitive package only long enough for Windows to request it.
class NativeShareCoordinator {
 public:
  explicit NativeShareCoordinator(HWND owner) : owner_(owner) {}

  /// Shows the Windows share UI with text and a PNG stream held only in memory.
  bool Present(const std::string& title, const std::string& text,
               const std::vector<uint8_t>& qr_png, std::string* error) {
    try {
      EnsureInitialized();
      if (pending_) {
        if (error != nullptr) {
          *error = "A Windows share request is already pending.";
        }
        return false;
      }

      winrt::com_ptr<IStream> memory_stream;
      memory_stream.attach(SHCreateMemStream(
          qr_png.data(), static_cast<UINT>(qr_png.size())));
      if (!memory_stream) {
        winrt::throw_hresult(E_OUTOFMEMORY);
      }

      IRandomAccessStream random_access_stream{nullptr};
      winrt::check_hresult(CreateRandomAccessStreamOverStream(
          memory_stream.get(), BSOS_DEFAULT,
          __uuidof(ABI::Windows::Storage::Streams::IRandomAccessStream),
          winrt::put_abi(random_access_stream)));

      pending_ = std::make_unique<PendingShare>(
          winrt::to_hstring(title), winrt::to_hstring(text),
          random_access_stream,
          RandomAccessStreamReference::CreateFromStream(random_access_stream));
      winrt::check_hresult(interop_->ShowShareUIForWindow(owner_));
      return true;
    } catch (const winrt::hresult_error& exception) {
      pending_.reset();
      if (error != nullptr) {
        *error = winrt::to_string(exception.message());
      }
      return false;
    }
  }

 private:
  /// Owns the text and stream references consumed by one DataRequested event.
  struct PendingShare {
    PendingShare(
        winrt::hstring share_title, winrt::hstring share_text,
        IRandomAccessStream share_stream, RandomAccessStreamReference share_bitmap)
        : title(std::move(share_title)),
          text(std::move(share_text)),
          stream(std::move(share_stream)),
          bitmap(std::move(share_bitmap)) {}

    winrt::hstring title;
    winrt::hstring text;
    IRandomAccessStream stream;
    RandomAccessStreamReference bitmap;
  };

  /// Acquires the per-window DataTransferManager and installs one data handler.
  void EnsureInitialized() {
    if (manager_) return;

    interop_ = winrt::get_activation_factory<
        DataTransferManager, IDataTransferManagerInterop>();
    winrt::check_hresult(interop_->GetForWindow(
        owner_,
        __uuidof(ABI::Windows::ApplicationModel::DataTransfer::
                     IDataTransferManager),
        winrt::put_abi(manager_)));
    data_requested_token_ = manager_.DataRequested(
        [this](const DataTransferManager&,
               const DataRequestedEventArgs& arguments) {
          HandleDataRequested(arguments);
        });
  }

  /// Copies the pending fields into the Windows DataPackage on demand.
  void HandleDataRequested(const DataRequestedEventArgs& arguments) {
    if (!pending_) {
      arguments.Request().FailWithDisplayText(
          L"The sensitive share package is no longer available.");
      return;
    }

    auto data = arguments.Request().Data();
    data.Properties().Title(pending_->title);
    data.SetText(pending_->text);
    data.SetBitmap(pending_->bitmap);

    // DataPackage now owns the copied text and stream reference. Release the
    // runner's sensitive references immediately after satisfying the request.
    pending_.reset();
  }

  HWND owner_;
  DataTransferManager manager_{nullptr};
  winrt::com_ptr<IDataTransferManagerInterop> interop_;
  winrt::event_token data_requested_token_{};
  std::unique_ptr<PendingShare> pending_;
};

/// Finds a string value in a StandardMethodCodec map.
const std::string* FindString(const flutter::EncodableMap& arguments,
                             const char* key) {
  const auto iterator = arguments.find(flutter::EncodableValue(key));
  if (iterator == arguments.end()) return nullptr;
  return std::get_if<std::string>(&iterator->second);
}

/// Finds PNG bytes in a StandardMethodCodec map.
const std::vector<uint8_t>* FindBytes(const flutter::EncodableMap& arguments,
                                     const char* key) {
  const auto iterator = arguments.find(flutter::EncodableValue(key));
  if (iterator == arguments.end()) return nullptr;
  return std::get_if<std::vector<uint8_t>>(&iterator->second);
}

}  // namespace

void RegisterChannel(flutter::FlutterEngine* engine, HWND owner) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          engine->messenger(), "google_code/native_account_share",
          &flutter::StandardMethodCodec::GetInstance());
  auto coordinator = std::make_shared<NativeShareCoordinator>(owner);

  channel->SetMethodCallHandler(
      [coordinator](const auto& call, auto result) {
        if (call.method_name() != "shareAccount") {
          result->NotImplemented();
          return;
        }

        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("invalid_share_payload",
                        "The native share payload is missing.");
          return;
        }
        const auto* title = FindString(*arguments, "title");
        const auto* text = FindString(*arguments, "text");
        const auto* qr_png = FindBytes(*arguments, "qrPng");
        if (title == nullptr || title->empty() || text == nullptr ||
            text->empty() || qr_png == nullptr || qr_png->empty() ||
            qr_png->size() > kMaximumQrBytes) {
          result->Error("invalid_share_payload",
                        "The native share payload is invalid.");
          return;
        }

        std::string error;
        if (!coordinator->Present(*title, *text, *qr_png, &error)) {
          result->Error("share_unavailable",
                        "The Windows share UI could not be presented.",
                        flutter::EncodableValue(error));
          return;
        }

        // Dart hides its material immediately while Windows owns the share UI.
        result->Success(flutter::EncodableValue("presented"));
      });
}

}  // namespace native_account_share
