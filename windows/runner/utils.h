#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and the Flutter library.
void CreateAndAttachConsole();

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Takes a UTF-8 encoded std::string and returns a std::wstring encoded in
// UTF-16. Returns an empty std::wstring on failure.
std::wstring Utf16FromUtf8(const std::string& utf8_string);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

// Result of running a child process synchronously.
struct CmdResult {
  unsigned long exit_code;  // DWORD compatible
  std::wstring output;      // captured stdout + stderr
};

// Runs |command_line| (via cmd.exe /C for shell semantics) and waits for it,
// returning the process exit code and combined stdout/stderr.
CmdResult RunCmdSync(const std::wstring& command_line);

// Returns true when the current process is running with elevated (Admin)
// privileges, which are required for split-tunnel route changes and some
// network cache operations on Windows.
bool IsElevated();

#endif  // RUNNER_UTILS_H_
