/**
 * @file agus_platform_linux.cpp
 * @brief Linux-specific platform stubs for CoMaps integration.
 *
 * This file provides minimal platform stubs needed for Linux that are not
 * provided by CoMaps' libplatform. Unlike Android, Linux uses CoMaps' own
 * platform implementation, so we only need to provide HTTP thread stubs.
 */

#if defined(__linux__) && !defined(__ANDROID__)

#include <string>
#include <cstdint>

// Forward declaration for HTTP thread (declared at file scope as expected)
class HttpThread;

namespace downloader {
  class IHttpThreadCallback;

  // HTTP thread stubs - in downloader namespace as expected by http_request.cpp
  // These are not provided by CoMaps' libplatform for our headless/embedded use case
  __attribute__((visibility("default"))) void DeleteNativeHttpThread(::HttpThread*) {
    // No-op - HTTP not supported in headless mode
  }

  __attribute__((visibility("default"))) ::HttpThread * CreateNativeHttpThread(
      std::string const & url, IHttpThreadCallback & callback, int64_t begRange,
      int64_t endRange, int64_t expectedSize, std::string const & postBody) {
    // Return nullptr - no HTTP support in headless mode
    // Map data should be pre-downloaded and loaded from local storage
    return nullptr;
  }
}

#endif // __linux__ && !__ANDROID__
