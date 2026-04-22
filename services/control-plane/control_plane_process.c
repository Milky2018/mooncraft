#include <moonbit.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/wait.h>

MOONBIT_FFI_EXPORT
int32_t moonbitcloud_shell_status(moonbit_bytes_t command) {
  int status = system((const char *)command);
  if (status < 0) {
    return 1;
  }
  if (WIFEXITED(status)) {
    return WEXITSTATUS(status);
  }
  return status;
}
