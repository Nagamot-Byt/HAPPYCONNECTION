#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <algorithm>
#include <iostream>
#include <sstream>
#include <vector>

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
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
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

std::wstring Utf16FromUtf8(const std::string& utf8_string) {
  if (utf8_string.empty()) return std::wstring();
  int target_length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(),
      (int)utf8_string.size(), NULL, 0);
  if (target_length <= 0) return std::wstring();
  std::wstring out(target_length, L'\0');
  int converted = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(),
      (int)utf8_string.size(), out.data(), target_length);
  if (converted <= 0) return std::wstring();
  return out;
}

static std::wstring Utf16FromProcessOutput(const std::string& output) {
  if (output.empty()) return std::wstring();

  std::string normalized = output;
  if (normalized.size() >= 3 &&
      static_cast<unsigned char>(normalized[0]) == 0xEF &&
      static_cast<unsigned char>(normalized[1]) == 0xBB &&
      static_cast<unsigned char>(normalized[2]) == 0xBF) {
    normalized.erase(0, 3);
  }

  std::wstring utf8 = Utf16FromUtf8(normalized);
  if (!utf8.empty()) return utf8;

  const int target_length = ::MultiByteToWideChar(
      CP_OEMCP, 0, normalized.data(), static_cast<int>(normalized.size()),
      nullptr, 0);
  if (target_length <= 0) return std::wstring();

  std::wstring out(target_length, L'\0');
  const int converted = ::MultiByteToWideChar(
      CP_OEMCP, 0, normalized.data(), static_cast<int>(normalized.size()),
      out.data(), target_length);
  if (converted <= 0) return std::wstring();
  return out;
}

CmdResult RunCmdSync(const std::wstring& command_line) {
  CmdResult result{1, L""};

  SECURITY_ATTRIBUTES sa{};
  sa.nLength = sizeof(SECURITY_ATTRIBUTES);
  sa.bInheritHandle = TRUE;
  sa.lpSecurityDescriptor = NULL;

  HANDLE h_read = NULL;
  HANDLE h_write = NULL;
  if (!CreatePipe(&h_read, &h_write, &sa, 0)) {
    return result;
  }
  SetHandleInformation(h_read, HANDLE_FLAG_INHERIT, 0);

  // Wrap command in cmd.exe /C so shell semantics work (built-ins, PATH, etc).
  std::wstringstream full_cmd;
  full_cmd << L"cmd.exe /C \"" << command_line << L"\"";
  std::wstring cmd_buf = full_cmd.str();
  std::vector<wchar_t> cmd_buf_mut(cmd_buf.begin(), cmd_buf.end());
  cmd_buf_mut.push_back(L'\0');

  STARTUPINFOW si{};
  si.cb = sizeof(STARTUPINFOW);
  si.hStdError = h_write;
  si.hStdOutput = h_write;
  si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  si.dwFlags |= STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
  si.wShowWindow = SW_HIDE;

  PROCESS_INFORMATION pi{};

  BOOL created = CreateProcessW(
      NULL, cmd_buf_mut.data(), NULL, NULL, TRUE,
      CREATE_NO_WINDOW, NULL, NULL, &si, &pi);

  CloseHandle(h_write);

  if (!created) {
    CloseHandle(h_read);
    return result;
  }

  std::string raw_output;
  constexpr DWORD kBufSize = 4096;
  char buffer[kBufSize];
  DWORD bytes_read = 0;
  while (ReadFile(h_read, buffer, sizeof(buffer), &bytes_read, NULL) &&
         bytes_read > 0) {
    raw_output.append(buffer, bytes_read);
  }
  result.output = Utf16FromProcessOutput(raw_output);

  DWORD wait_result = WaitForSingleObject(pi.hProcess, 15000);
  DWORD code = 1;
  if (wait_result == WAIT_TIMEOUT) {
    TerminateProcess(pi.hProcess, 1);
    result.output = L"Error: El comando excedió el tiempo límite (timeout) de 15 segundos.";
  } else {
    GetExitCodeProcess(pi.hProcess, &code);
  }
  result.exit_code = code;

  CloseHandle(h_read);
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);
  return result;
}

bool IsElevated() {
  BOOL elevated = FALSE;
  HANDLE token = NULL;
  if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    TOKEN_ELEVATION elevation{};
    DWORD sz = sizeof(TOKEN_ELEVATION);
    if (GetTokenInformation(token, TokenElevation, &elevation, sz, &sz)) {
      elevated = elevation.TokenIsElevated;
    }
    CloseHandle(token);
  }
  return elevated != FALSE;
}
