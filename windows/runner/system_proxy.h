#ifndef RUNNER_SYSTEM_PROXY_H_
#define RUNNER_SYSTEM_PROXY_H_

#include <windows.h>
#include <winhttp.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cwctype>
#include <sstream>
#include <string>
#include <vector>

namespace azusa {

inline std::wstring Wide(const std::string& text) {
  const int length = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                        static_cast<int>(text.size()), nullptr, 0);
  std::wstring value(length, 0);
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      value.data(), length);
  return value;
}

inline std::string Utf8(const std::wstring& text) {
  const int length = WideCharToMultiByte(CP_UTF8, 0, text.data(),
      static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  std::string value(length, 0);
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      value.data(), length, nullptr, nullptr);
  return value;
}

inline std::wstring Lower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
  return value;
}

inline std::vector<std::wstring> Tokens(std::wstring value) {
  std::replace(value.begin(), value.end(), L';', L' ');
  std::wistringstream stream(value);
  std::vector<std::wstring> tokens;
  std::wstring token;
  while (stream >> token) tokens.push_back(token);
  return tokens;
}

inline bool Wildcard(const std::wstring& pattern, const std::wstring& value) {
  size_t p = 0, v = 0, star = std::wstring::npos, restart = 0;
  while (v < value.size()) {
    if (p < pattern.size() && (pattern[p] == L'?' || pattern[p] == value[v])) {
      ++p;
      ++v;
    } else if (p < pattern.size() && pattern[p] == L'*') {
      star = p++;
      restart = v;
    } else if (star != std::wstring::npos) {
      p = star + 1;
      v = ++restart;
    } else {
      return false;
    }
  }
  while (p < pattern.size() && pattern[p] == L'*') ++p;
  return p == pattern.size();
}

inline void RegisterSystemProxy(flutter::BinaryMessenger* messenger) {
  flutter::MethodChannel<flutter::EncodableValue> channel(
      messenger, "azusa/system_proxy",
      &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() != "resolve") {
      result->NotImplemented();
      return;
    }
    const auto* argument = call.arguments();
    const auto* text = argument ? std::get_if<std::string>(argument) : nullptr;
    if (!text) {
      result->Error("proxy_error", "Invalid URL");
      return;
    }
    const auto url = Wide(*text);
    URL_COMPONENTS parts = {};
    parts.dwStructSize = sizeof(parts);
    parts.dwHostNameLength = static_cast<DWORD>(-1);
    if (!WinHttpCrackUrl(url.c_str(), 0, 0, &parts)) {
      result->Error("proxy_error", "Invalid URL");
      return;
    }
    WINHTTP_CURRENT_USER_IE_PROXY_CONFIG config = {};
    if (!WinHttpGetIEProxyConfigForCurrentUser(&config)) {
      result->Error("proxy_error", "Unable to read Windows proxy settings");
      return;
    }
    const bool automatic = config.fAutoDetect || config.lpszAutoConfigUrl;
    const std::wstring proxy = config.lpszProxy ? config.lpszProxy : L"";
    const std::wstring bypass = config.lpszProxyBypass ? config.lpszProxyBypass : L"";
    if (config.lpszAutoConfigUrl) GlobalFree(config.lpszAutoConfigUrl);
    if (config.lpszProxy) GlobalFree(config.lpszProxy);
    if (config.lpszProxyBypass) GlobalFree(config.lpszProxyBypass);

    if (automatic) {
      result->Error("unsupported_proxy",
          "Windows PAC/WPAD is not supported; use a fixed HTTP proxy");
      return;
    }
    const auto host = Lower(std::wstring(parts.lpszHostName, parts.dwHostNameLength));
    const auto host_port = host + L":" + std::to_wstring(parts.nPort);
    bool direct = false;
    for (const auto& token : Tokens(Lower(bypass))) {
      if ((token == L"<local>" && host.find(L'.') == std::wstring::npos &&
           host.find(L':') == std::wstring::npos) ||
          Wildcard(token, host) || Wildcard(token, host_port)) {
        direct = true;
        break;
      }
    }
    std::wstring selected;
    const auto scheme = parts.nScheme == INTERNET_SCHEME_HTTPS ? L"https" : L"http";
    if (!direct) {
      for (const auto& token : Tokens(proxy)) {
        const auto equal = token.find(L'=');
        if (equal == std::wstring::npos) {
          selected = token;
        } else if (Lower(token.substr(0, equal)) == scheme) {
          selected = token.substr(equal + 1);
          break;
        }
      }
    }
    std::string route = "direct://";
    if (!selected.empty()) {
      if (selected.find(L"://") == std::wstring::npos) selected = L"http://" + selected;
      route = Utf8(selected);
    }
    result->Success(flutter::EncodableValue(flutter::EncodableList{
        flutter::EncodableValue(route)}));
  });
}

}  // namespace azusa

#endif  // RUNNER_SYSTEM_PROXY_H_
