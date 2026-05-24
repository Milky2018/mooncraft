#include <moonbit.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

MOONBIT_FFI_EXPORT
moonbit_bytes_t mooncraft_random_hex(int32_t byte_count) {
  if (byte_count <= 0) {
    return moonbit_empty_int8_array;
  }

  FILE *file = fopen("/dev/urandom", "rb");
  if (!file) {
    return moonbit_empty_int8_array;
  }

  size_t raw_len = (size_t) byte_count;
  uint8_t *raw = (uint8_t *) malloc(raw_len);
  if (!raw) {
    fclose(file);
    return moonbit_empty_int8_array;
  }

  size_t read_len = fread(raw, 1, raw_len, file);
  fclose(file);
  if (read_len != raw_len) {
    free(raw);
    return moonbit_empty_int8_array;
  }

  static const char HEX[] = "0123456789abcdef";
  moonbit_bytes_t out = moonbit_make_bytes_raw(byte_count * 2);
  for (int32_t i = 0; i < byte_count; ++i) {
    out[i * 2] = HEX[(raw[i] >> 4) & 0x0f];
    out[i * 2 + 1] = HEX[raw[i] & 0x0f];
  }
  free(raw);
  return out;
}
