/* SPDX-License-Identifier: Apache-2.0 */
#include <libpldm/char16.h>

#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
static_assert(sizeof(char16_t) == sizeof(uint16_t), "UTF-16 code unit size");
static_assert(alignof(char16_t) == alignof(uint16_t),
              "UTF-16 code unit alignment");
#else
_Static_assert(sizeof(char16_t) == sizeof(uint16_t), "UTF-16 code unit size");
_Static_assert(_Alignof(char16_t) == _Alignof(uint16_t),
               "UTF-16 code unit alignment");
#endif

int main(void) {
  const char16_t text[] = u"\U0001f600";

  if (sizeof(text) != 6 || text[0] != 0xd83d || text[1] != 0xde00 ||
      text[2] != 0) {
    return 1;
  }
  puts("UTF-16 type size, alignment and surrogate pair: OK");
  return 0;
}
