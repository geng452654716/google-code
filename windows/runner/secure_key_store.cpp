#include "secure_key_store.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <wincred.h>

#include <cstdint>
#include <cstring>
#include <memory>
#include <utility>
#include <vector>

namespace {

constexpr wchar_t kCredentialTarget[] =
    L"com.gengyujian.google-code.quick-unlock.v1";
constexpr wchar_t kCredentialUser[] = L"google-code-vault";
constexpr size_t kQuickUnlockKeyLength = 32;

/// Owns and clears a Credential Manager result before releasing it.
class CredentialScope {
 public:
  explicit CredentialScope(PCREDENTIALW credential) : credential_(credential) {}
  ~CredentialScope() {
    if (credential_ != nullptr) {
      if (credential_->CredentialBlob != nullptr &&
          credential_->CredentialBlobSize > 0) {
        SecureZeroMemory(credential_->CredentialBlob,
                         credential_->CredentialBlobSize);
      }
      CredFree(credential_);
    }
  }

  CredentialScope(const CredentialScope&) = delete;
  CredentialScope& operator=(const CredentialScope&) = delete;

 private:
  PCREDENTIALW credential_;
};

enum class CredentialReadStatus { kSuccess, kNotFound, kInvalid, kFailed };

/// Carries an explicit Credential Manager outcome without relying on a stale
/// thread-local GetLastError value after validation or cleanup work.
struct CredentialReadResult {
  CredentialReadStatus status;
  std::vector<uint8_t> bytes;
};

/// Reads and validates the fixed-size quick-unlock DEK.
CredentialReadResult ReadQuickUnlockKey() {
  PCREDENTIALW credential = nullptr;
  if (!CredReadW(kCredentialTarget, CRED_TYPE_GENERIC, 0, &credential)) {
    const DWORD error = GetLastError();
    return {error == ERROR_NOT_FOUND ? CredentialReadStatus::kNotFound
                                     : CredentialReadStatus::kFailed,
            {}};
  }
  CredentialScope scope(credential);
  if (credential->CredentialBlob == nullptr ||
      credential->CredentialBlobSize != kQuickUnlockKeyLength) {
    return {CredentialReadStatus::kInvalid, {}};
  }
  return {CredentialReadStatus::kSuccess,
          std::vector<uint8_t>(
              credential->CredentialBlob,
              credential->CredentialBlob + credential->CredentialBlobSize)};
}

/// Writes the fixed quick-unlock DEK as a local-machine persisted credential.
bool WriteQuickUnlockKey(const std::vector<uint8_t>& bytes) {
  if (bytes.size() != kQuickUnlockKeyLength) {
    return false;
  }
  CREDENTIALW credential{};
  credential.Type = CRED_TYPE_GENERIC;
  credential.TargetName = const_cast<wchar_t*>(kCredentialTarget);
  credential.CredentialBlobSize = static_cast<DWORD>(bytes.size());
  credential.CredentialBlob = const_cast<LPBYTE>(bytes.data());
  credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
  credential.UserName = const_cast<wchar_t*>(kCredentialUser);
  return CredWriteW(&credential, 0) == TRUE;
}

/// Deletes the quick-unlock credential; a missing item is already disabled.
bool DeleteQuickUnlockKey() {
  if (CredDeleteW(kCredentialTarget, CRED_TYPE_GENERIC, 0)) {
    return true;
  }
  return GetLastError() == ERROR_NOT_FOUND;
}

}  // namespace

void RegisterSecureKeyStoreChannel(flutter::FlutterEngine* engine) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          engine->messenger(), "google_code/secure_key_store",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "contains") {
      PCREDENTIALW credential = nullptr;
      if (CredReadW(kCredentialTarget, CRED_TYPE_GENERIC, 0, &credential)) {
        CredentialScope scope(credential);
        result->Success(flutter::EncodableValue(true));
        return;
      }
      const DWORD error = GetLastError();
      if (error == ERROR_NOT_FOUND) {
        result->Success(flutter::EncodableValue(false));
      } else {
        result->Error("secure_store_read_failed",
                      "Unable to inspect quick unlock material.");
      }
      return;
    }
    if (call.method_name() == "read") {
      auto read_result = ReadQuickUnlockKey();
      switch (read_result.status) {
        case CredentialReadStatus::kSuccess:
          result->Success(
              flutter::EncodableValue(std::move(read_result.bytes)));
          return;
        case CredentialReadStatus::kNotFound:
          result->Success();
          return;
        case CredentialReadStatus::kInvalid:
          result->Error("invalid_key",
                        "Stored quick unlock material is invalid.");
          return;
        case CredentialReadStatus::kFailed:
          result->Error("secure_store_read_failed",
                        "Unable to read quick unlock material.");
          return;
      }
    }
    if (call.method_name() == "write") {
      const auto* bytes =
          std::get_if<std::vector<uint8_t>>(call.arguments());
      if (bytes == nullptr || bytes->size() != kQuickUnlockKeyLength) {
        result->Error("invalid_key", "Quick unlock key is invalid.");
        return;
      }
      if (!WriteQuickUnlockKey(*bytes)) {
        result->Error("secure_store_write_failed",
                      "Unable to save quick unlock material.");
        return;
      }
      result->Success();
      return;
    }
    if (call.method_name() == "delete") {
      if (!DeleteQuickUnlockKey()) {
        result->Error("secure_store_delete_failed",
                      "Unable to delete quick unlock material.");
        return;
      }
      result->Success();
      return;
    }
    result->NotImplemented();
  });
}
