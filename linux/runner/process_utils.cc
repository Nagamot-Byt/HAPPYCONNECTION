#include "process_utils.h"

#include <sys/wait.h>
#include <unistd.h>

#include <vector>

namespace {

gboolean spawn_argv(const std::vector<std::string>& args,
                    gchar** stdout_out,
                    gchar** stderr_out,
                    gint* exit_code) {
  if (args.empty()) {
    if (stdout_out) *stdout_out = nullptr;
    if (stderr_out) *stderr_out = g_strdup("No se especificó ningún programa.");
    if (exit_code) *exit_code = -1;
    return FALSE;
  }

  std::vector<gchar*> argv;
  argv.reserve(args.size() + 1);
  for (const auto& arg : args) {
    argv.push_back(const_cast<gchar*>(arg.c_str()));
  }
  argv.push_back(nullptr);

  gint wait_status = 0;
  g_autoptr(GError) error = nullptr;
  const gboolean ok = g_spawn_sync(
      nullptr, argv.data(), nullptr, G_SPAWN_SEARCH_PATH, nullptr, nullptr,
      stdout_out, stderr_out, &wait_status, &error);

  if (!ok) {
    if (stdout_out) *stdout_out = nullptr;
    if (stderr_out) *stderr_out = g_strdup(error ? error->message
                                                 : "No se pudo ejecutar el programa.");
    if (exit_code) *exit_code = -1;
    return FALSE;
  }

  if (exit_code) {
    if (WIFEXITED(wait_status)) {
      *exit_code = WEXITSTATUS(wait_status);
    } else if (WIFSIGNALED(wait_status)) {
      *exit_code = 128 + WTERMSIG(wait_status);
    } else {
      *exit_code = -1;
    }
  }
  return TRUE;
}

void clear_outputs(gchar** stdout_out, gchar** stderr_out) {
  if (stdout_out) {
    g_free(*stdout_out);
    *stdout_out = nullptr;
  }
  if (stderr_out) {
    g_free(*stderr_out);
    *stderr_out = nullptr;
  }
}

}  // namespace

gboolean run_program(const std::vector<std::string>& args,
                     gchar** stdout_out,
                     gchar** stderr_out,
                     gint* exit_code) {
  return spawn_argv(args, stdout_out, stderr_out, exit_code);
}

gboolean run_privileged(const std::vector<std::string>& args,
                        gchar** stdout_out,
                        gchar** stderr_out,
                        gint* exit_code) {
  if (process_is_root()) {
    return spawn_argv(args, stdout_out, stderr_out, exit_code);
  }

  std::vector<std::string> sudo_args{"sudo", "-n"};
  sudo_args.insert(sudo_args.end(), args.begin(), args.end());
  if (spawn_argv(sudo_args, stdout_out, stderr_out, exit_code) &&
      exit_code && *exit_code == 0) {
    return TRUE;
  }

  clear_outputs(stdout_out, stderr_out);
  std::vector<std::string> pkexec_args{"pkexec"};
  pkexec_args.insert(pkexec_args.end(), args.begin(), args.end());
  return spawn_argv(pkexec_args, stdout_out, stderr_out, exit_code);
}

gboolean process_is_root() { return geteuid() == 0; }
