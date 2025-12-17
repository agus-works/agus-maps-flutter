#include "platform/platform.hpp"
#include "platform/locale.hpp"
#include "platform/http_client.hpp"
#include "platform/secure_storage.hpp"
#include "platform/get_text_by_id.hpp"
#include <string>
#include <vector>
#include <unordered_map>

class AgusPlatform : public Platform
{
public:
  AgusPlatform() = default;

  void Init(std::string const & apkPath, std::string const & storagePath)
  {
      m_resourcesDir = apkPath;
      m_writableDir = storagePath;
      m_settingsDir = storagePath; 
      m_tmpDir = storagePath + "/tmp/";
      
      // Ensure writable dir ends with slash? 
      // base::AddSlashIfNeeded is not easily accessible unless I include base/string_utils.hpp
      if (!m_writableDir.empty() && m_writableDir.back() != '/') m_writableDir += '/';
      if (!m_settingsDir.empty() && m_settingsDir.back() != '/') m_settingsDir += '/';
      if (!m_tmpDir.empty() && m_tmpDir.back() != '/') m_tmpDir += '/';
      // m_resourcesDir (APK path) should NOT end with slash.
  }
  
  // New init function that takes separate resource and writable paths
  // This is used when we have extracted data files to the filesystem
  void InitPaths(std::string const & resourcePath, std::string const & writablePath)
  {
      m_resourcesDir = resourcePath;
      m_writableDir = writablePath;
      m_settingsDir = writablePath; 
      m_tmpDir = writablePath + "/tmp/";
      
      // Ensure directories end with slash
      if (!m_resourcesDir.empty() && m_resourcesDir.back() != '/') m_resourcesDir += '/';
      if (!m_writableDir.empty() && m_writableDir.back() != '/') m_writableDir += '/';
      if (!m_settingsDir.empty() && m_settingsDir.back() != '/') m_settingsDir += '/';
      if (!m_tmpDir.empty() && m_tmpDir.back() != '/') m_tmpDir += '/';
  }
};

static AgusPlatform g_platform;

Platform & GetPlatform()
{
  return g_platform;
}

extern "C" void AgusPlatform_Init(const char* apkPath, const char* storagePath)
{
    g_platform.Init(apkPath, storagePath);
}

extern "C" void AgusPlatform_InitPaths(const char* resourcePath, const char* writablePath)
{
    g_platform.InitPaths(resourcePath, writablePath);
}

// Stubs for missing Platform methods
uint8_t Platform::GetBatteryLevel() { return 100; }
Platform::ChargingStatus Platform::GetChargingStatus() { return Platform::ChargingStatus::Plugged; }
Platform::EConnectionType Platform::ConnectionStatus() { return Platform::EConnectionType::CONNECTION_WIFI; }

std::string Platform::GetMemoryInfo() const { return ""; }
std::string Platform::DeviceName() const { return "AgusMap"; }
std::string Platform::DeviceModel() const { return "Android"; }
std::string Platform::Version() const { return "1.0.0"; }
int32_t Platform::IntVersion() const { return 100; }

// C++ linkage - Android threading stubs (not using JVM)
__attribute__((visibility("default"))) void AndroidThreadAttachToJVM() {}
__attribute__((visibility("default"))) void AndroidThreadDetachFromJVM() {}

// Android system languages stub
__attribute__((visibility("default"))) std::vector<std::string> GetAndroidSystemLanguages() {
  return {"en"};
}

// Forward declarations for HTTP (HttpThread is declared at file scope)
class HttpThread;

namespace downloader {
  class IHttpThreadCallback;
  
  // HTTP thread stubs - in downloader namespace as expected by http_request.cpp
  __attribute__((visibility("default"))) void DeleteNativeHttpThread(::HttpThread*) {}

  __attribute__((visibility("default"))) ::HttpThread * CreateNativeHttpThread(
      std::string const & url, IHttpThreadCallback & callback, int64_t begRange,
      int64_t endRange, int64_t expectedSize, std::string const & postBody) {
    // Return nullptr - no HTTP support in headless mode
    return nullptr;
  }
}

namespace platform {
  __attribute__((visibility("default"))) std::string GetLocalizedTypeName(std::string const & type) { return type; }
  __attribute__((visibility("default"))) std::string GetLocalizedBrandName(std::string const & brand) { return brand; }
  __attribute__((visibility("default"))) std::string GetLocalizedString(std::string const & key) { return key; }
  __attribute__((visibility("default"))) std::string GetCurrencySymbol(std::string const & currencyCode) { return currencyCode; }
  __attribute__((visibility("default"))) std::string GetLocalizedMyPositionBookmarkName() { return "My Position"; }
  
  // Locale stub
  __attribute__((visibility("default"))) Locale GetCurrentLocale() {
    Locale locale;
    locale.m_language = "en";
    locale.m_country = "US";
    locale.m_currency = "USD";
    locale.m_decimalSeparator = ".";
    locale.m_groupingSeparator = ",";
    return locale;
  }

  // HttpClient stub
  __attribute__((visibility("default"))) bool HttpClient::RunHttpRequest() {
    // No HTTP support in headless mode
    return false;
  }

  // SecureStorage stubs
  __attribute__((visibility("default"))) void SecureStorage::Save(std::string const & key, std::string const & value) {
    // No-op in headless mode
  }
  __attribute__((visibility("default"))) bool SecureStorage::Load(std::string const & key, std::string & value) {
    return false;
  }
  __attribute__((visibility("default"))) void SecureStorage::Remove(std::string const & key) {
    // No-op in headless mode
  }

  // Override GetTextByIdFactory to return a stub implementation instead of asserting
  // This allows the Framework to initialize without the localization JSON files
  // We use --allow-multiple-definition linker flag, and our .o file is linked before libplatform.a
  TGetTextByIdPtr GetTextByIdFactory(TextSource, std::string const &)
  {
    // Return nullptr - callers check for null and handle gracefully
    return nullptr;
  }
  
  TGetTextByIdPtr ForTestingGetTextByIdFactory(std::string const &, std::string const &)
  {
    return nullptr;
  }

  bool GetJsonBuffer(TextSource, std::string const &, std::string &)
  {
    return false;
  }
}
