#ifndef PROCESS_UTILS_H_
#define PROCESS_UTILS_H_

#include <glib.h>

#include <string>
#include <vector>

/**
 * Runs a program directly (no shell) and captures stdout/stderr.
 */
gboolean run_program(const std::vector<std::string>& args,
                     gchar** stdout_out,
                     gchar** stderr_out,
                     gint* exit_code);

/**
 * Runs a program with root privileges. Uses the current process when it is
 * already root, otherwise tries `sudo -n` and finally `pkexec`.
 */
gboolean run_privileged(const std::vector<std::string>& args,
                        gchar** stdout_out,
                        gchar** stderr_out,
                        gint* exit_code);

/**
 * Returns true when the current process runs as root.
 */
gboolean process_is_root();

#endif  // PROCESS_UTILS_H_
