/* SPDX-License-Identifier: Apache-2.0 */
#include <stddef.h>
#include <stdio.h>
#include <string.h>

/* Exercise the Windows fallback even on a Unix validation host. Include
 * system headers first so the test does not impersonate Windows libc.
 */
#ifndef _WIN32
#define _WIN32
#endif
#include "environ/string.h"

int main(void) {
  const unsigned char data[] = {0x01, 0, 0, 0x02, 0};
  const unsigned char term[] = {0, 0};

  if (libpldm_memmem(data, sizeof(data), term, sizeof(term)) != data + 1 ||
      libpldm_memmem(data, 1, term, sizeof(term)) != NULL ||
      libpldm_memmem(data, 0, term, sizeof(term)) != NULL ||
      libpldm_memmem(data, sizeof(data), term, 0) != data ||
      libpldm_memmem(data + 2, 3, term, sizeof(term)) != NULL ||
      libpldm_memmem(data, 3, term, sizeof(term)) != data + 1) {
    fputs("Bounded substring fallback failed\n", stderr);
    return 1;
  }
  puts("Windows substring fallback boundaries: OK");
  return 0;
}
