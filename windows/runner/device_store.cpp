#include "device_store.h"

#include <windows.h>
#include <shlobj.h>
#include <wincrypt.h>
#include <flutter/standard_method_codec.h>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr size_t kMaxSize = 512000;

std::filesystem::path VaultPath() {
  PWSTR folder = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &folder))) {
    throw std::runtime_error("Storage unavailable");
  }
  std::filesystem::path directory = std::filesystem::path(folder) / L"Qiyou";
  CoTaskMemFree(folder);
  std::filesystem::create_directories(directory);
  return directory / L"accounts.dpapi";
}

std::string Decrypt(const std::vector<BYTE>& bytes) {
  DATA_BLOB encrypted{static_cast<DWORD>(bytes.size()), const_cast<BYTE*>(bytes.data())};
  DATA_BLOB plain{};
  if (!CryptUnprotectData(&encrypted, nullptr, nullptr, nullptr, nullptr,
                         CRYPTPROTECT_UI_FORBIDDEN, &plain)) {
    throw std::runtime_error("Storage unavailable");
  }
  std::string value(reinterpret_cast<char*>(plain.pbData), plain.cbData);
  SecureZeroMemory(plain.pbData, plain.cbData);
  LocalFree(plain.pbData);
  return value;
}

void Write(const std::filesystem::path& path, const std::string& value) {
  if (value.size() > kMaxSize) throw std::runtime_error("Invalid value");
  DATA_BLOB plain{static_cast<DWORD>(value.size()),
                  reinterpret_cast<BYTE*>(const_cast<char*>(value.data()))};
  DATA_BLOB encrypted{};
  if (!CryptProtectData(&plain, L"Qiyou", nullptr, nullptr, nullptr,
                        CRYPTPROTECT_UI_FORBIDDEN, &encrypted)) {
    throw std::runtime_error("Storage unavailable");
  }
  const auto temporary = std::filesystem::path(path.wstring() + L".tmp");
  std::ofstream stream(temporary, std::ios::binary | std::ios::trunc);
  stream.write(reinterpret_cast<const char*>(encrypted.pbData), encrypted.cbData);
  stream.close();
  LocalFree(encrypted.pbData);
  if (!stream || !MoveFileExW(temporary.c_str(), path.c_str(),
                             MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    std::filesystem::remove(temporary);
    throw std::runtime_error("Storage unavailable");
  }
}
}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateDeviceStore(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "app.qiyou/device", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    try {
      const auto path = VaultPath();
      if (call.method_name() == "read") {
        if (!std::filesystem::exists(path)) {
          result->Success();
          return;
        }
        const auto size = std::filesystem::file_size(path);
        if (size == 0 || size > kMaxSize + 4096) throw std::runtime_error("Invalid data");
        std::ifstream stream(path, std::ios::binary);
        if (!stream) throw std::runtime_error("Storage unavailable");
        const std::vector<BYTE> bytes((std::istreambuf_iterator<char>(stream)), {});
        result->Success(flutter::EncodableValue(Decrypt(bytes)));
      } else if (call.method_name() == "write") {
        const auto* value = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
        if (!value) throw std::runtime_error("Invalid value");
        Write(path, *value);
        result->Success();
      } else if (call.method_name() == "delete") {
        std::filesystem::remove(path);
        result->Success();
      } else {
        result->NotImplemented();
      }
    } catch (...) {
      result->Error("SECURE_STORAGE", "本机安全存储不可用");
    }
  });
  return channel;
}
