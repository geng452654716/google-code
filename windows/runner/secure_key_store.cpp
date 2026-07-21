#include "secure_key_store.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <wincred.h>

#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace {

constexpr wchar_t kCredentialTarget[] =
    L"com.gengyujian.google-code.quick-unlock.v1";
constexpr wchar_t kCloudCredentialPrefix[] =
    L"com.gengyujian.google-code.cloud-secret.";
constexpr wchar_t kCredentialUser[] = L"google-code-vault";
constexpr size_t kQuickUnlockKeyLength = 32;
constexpr size_t kMaxCloudSecretLength = 4096;

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

/// Clears temporary secret bytes before their allocation is released.
void ClearBytes(std::vector<uint8_t>* bytes) {
  if (bytes != nullptr && !bytes->empty()) {
    SecureZeroMemory(bytes->data(), bytes->size());
    bytes->clear();
  }
}

/// Reads a generic credential and applies caller-defined size constraints.
CredentialReadResult ReadCredential(const wchar_t* target, size_t minimum_size,
                                    size_t maximum_size) {
  PCREDENTIALW credential = nullptr;
  if (!CredReadW(target, CRED_TYPE_GENERIC, 0, &credential)) {
    const DWORD error = GetLastError();
    return {error == ERROR_NOT_FOUND ? CredentialReadStatus::kNotFound
                                     : CredentialReadStatus::kFailed,
            {}};
  }
  CredentialScope scope(credential);
  if (credential->CredentialBlob == nullptr ||
      credential->CredentialBlobSize < minimum_size ||
      credential->CredentialBlobSize > maximum_size) {
    return {CredentialReadStatus::kInvalid, {}};
  }
  return {CredentialReadStatus::kSuccess,
          std::vector<uint8_t>(
              credential->CredentialBlob,
              credential->CredentialBlob + credential->CredentialBlobSize)};
}

/// Writes one local-machine persisted generic credential.
bool WriteCredential(const wchar_t* target,
                     const std::vector<uint8_t>& bytes) {
  CREDENTIALW credential{};
  credential.Type = CRED_TYPE_GENERIC;
  credential.TargetName = const_cast<wchar_t*>(target);
  credential.CredentialBlobSize = static_cast<DWORD>(bytes.size());
  credential.CredentialBlob = const_cast<LPBYTE>(bytes.data());
  credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
  credential.UserName = const_cast<wchar_t*>(kCredentialUser);
  return CredWriteW(&credential, 0) == TRUE;
}

/// Deletes a generic credential; a missing item is already disabled.
bool DeleteCredential(const wchar_t* target) {
  if (CredDeleteW(target, CRED_TYPE_GENERIC, 0)) {
    return true;
  }
  return GetLastError() == ERROR_NOT_FOUND;
}

/// Reads and validates the fixed-size quick-unlock DEK.
CredentialReadResult ReadQuickUnlockKey() {
  return ReadCredential(kCredentialTarget, kQuickUnlockKeyLength,
                        kQuickUnlockKeyLength);
}

/// Writes the fixed quick-unlock DEK as a local-machine persisted credential.
bool WriteQuickUnlockKey(const std::vector<uint8_t>& bytes) {
  return bytes.size() == kQuickUnlockKeyLength &&
         WriteCredential(kCredentialTarget, bytes);
}

/// Deletes the quick-unlock credential; a missing item is already disabled.
bool DeleteQuickUnlockKey() { return DeleteCredential(kCredentialTarget); }

/// Restricts native credential identifiers to the application-owned namespace.
bool IsValidCloudSecretKey(const std::string& key) {
  if (key.empty() || key.size() > 128) {
    return false;
  }
  for (size_t index = 0; index < key.size(); ++index) {
    const char value = key[index];
    const bool is_lower = value >= 'a' && value <= 'z';
    const bool is_number = value >= '0' && value <= '9';
    const bool is_separator = index > 0 &&
                              (value == '.' || value == '_' || value == '-');
    if (!is_lower && !is_number && !is_separator) {
      return false;
    }
  }
  return true;
}

/// Converts a validated ASCII key to its Credential Manager target.
std::wstring CloudSecretTarget(const std::string& key) {
  return std::wstring(kCloudCredentialPrefix) +
         std::wstring(key.begin(), key.end());
}

/// Reads a string field from a standard method-channel argument map.
const std::string* ReadStringArgument(const flutter::EncodableValue* arguments,
                                      const char* name) {
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) {
    return nullptr;
  }
  const auto iterator = map->find(flutter::EncodableValue(name));
  if (iterator == map->end()) {
    return nullptr;
  }
  return std::get_if<std::string>(&iterator->second);
}

/// Reads binary bytes from a standard method-channel argument map.
const std::vector<uint8_t>* ReadBytesArgument(
    const flutter::EncodableValue* arguments, const char* name) {
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) {
    return nullptr;
  }
  const auto iterator = map->find(flutter::EncodableValue(name));
  if (iterator == map->end()) {
    return nullptr;
  }
  return std::get_if<std::vector<uint8_t>>(&iterator->second);
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
    if (call.method_name() == "readSecret") {
      const auto* key = ReadStringArgument(call.arguments(), "key");
      if (key == nullptr || !IsValidCloudSecretKey(*key)) {
        result->Error("invalid_secret", "Device secret key is invalid.");
        return;
      }
      const std::wstring target = CloudSecretTarget(*key);
      auto read_result = ReadCredential(target.c_str(), 1,
                                        kMaxCloudSecretLength);
      switch (read_result.status) {
        case CredentialReadStatus::kSuccess:
          result->Success(
              flutter::EncodableValue(std::move(read_result.bytes)));
          return;
        case CredentialReadStatus::kNotFound:
          result->Success();
          return;
        case CredentialReadStatus::kInvalid:
          result->Error("invalid_secret", "Stored device secret is invalid.");
          return;
        case CredentialReadStatus::kFailed:
          result->Error("secure_store_read_failed",
                        "Unable to read device secret.");
          return;
      }
    }
    if (call.method_name() == "writeSecret") {
      const auto* key = ReadStringArgument(call.arguments(), "key");
      const auto* bytes = ReadBytesArgument(call.arguments(), "value");
      if (key == nullptr || !IsValidCloudSecretKey(*key) || bytes == nullptr ||
          bytes->empty() || bytes->size() > kMaxCloudSecretLength) {
        result->Error("invalid_secret", "Device secret is invalid.");
        return;
      }
      const std::wstring target = CloudSecretTarget(*key);
      std::vector<uint8_t> temporary(*bytes);
      const bool written = WriteCredential(target.c_str(), temporary);
      ClearBytes(&temporary);
      if (!written) {
        result->Error("secure_store_write_failed",
                      "Unable to save device secret.");
        return;
      }
      result->Success();
      return;
    }
    if (call.method_name() == "deleteSecret") {
      const auto* key = ReadStringArgument(call.arguments(), "key");
      if (key == nullptr || !IsValidCloudSecretKey(*key)) {
        result->Error("invalid_secret", "Device secret key is invalid.");
        return;
      }
      const std::wstring target = CloudSecretTarget(*key);
      if (!DeleteCredential(target.c_str())) {
        result->Error("secure_store_delete_failed",
                      "Unable to delete device secret.");
        return;
      }
      result->Success();
      return;
    }
    result->NotImplemented();
  });
}
