#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>
#include <shlwapi.h>

#include <iostream>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length <= 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

void RegisterFileAssociation() {
  // Best-effort, ignore failures. Requires shlwapi
  // ProgID
  const wchar_t* progId = L"Dalimaster.daliproj";
  const wchar_t* ext = L".daliproj";
  wchar_t modulePath[MAX_PATH] = {0};
  if (!::GetModuleFileNameW(nullptr, modulePath, MAX_PATH)) {
    return;
  }
  // HKCU\Software\Classes\Dalimaster.daliproj
  HKEY hKey;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Classes\\Dalimaster.daliproj", 0, nullptr, 0, KEY_WRITE, nullptr, &hKey, nullptr) == ERROR_SUCCESS) {
    RegSetValueExW(hKey, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE*>(L"DALI Project"), sizeof(wchar_t) * (wcslen(L"DALI Project") + 1));
    HKEY iconKey;
    if (RegCreateKeyExW(hKey, L"DefaultIcon", 0, nullptr, 0, KEY_WRITE, nullptr, &iconKey, nullptr) == ERROR_SUCCESS) {
      RegSetValueExW(iconKey, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE*>(modulePath), sizeof(wchar_t) * (wcslen(modulePath) + 1));
      RegCloseKey(iconKey);
    }
    HKEY shellKey;
    if (RegCreateKeyExW(hKey, L"shell\\open\\command", 0, nullptr, 0, KEY_WRITE, nullptr, &shellKey, nullptr) == ERROR_SUCCESS) {
      wchar_t cmd[MAX_PATH * 2];
      wsprintfW(cmd, L"\"%s\" \"%%1\"", modulePath);
      RegSetValueExW(shellKey, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE*>(cmd), sizeof(wchar_t) * (wcslen(cmd) + 1));
      RegCloseKey(shellKey);
    }
    RegCloseKey(hKey);
  }
  // HKCU\Software\Classes\.daliproj -> Dalimaster.daliproj
  if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Classes\\.daliproj", 0, nullptr, 0, KEY_WRITE, nullptr, &hKey, nullptr) == ERROR_SUCCESS) {
    RegSetValueExW(hKey, nullptr, 0, REG_SZ, reinterpret_cast<const BYTE*>(progId), sizeof(wchar_t) * (wcslen(progId) + 1));
    RegCloseKey(hKey);
  }
  // Notify shell
  ::SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}
