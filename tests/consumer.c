/* SPDX-License-Identifier: Apache-2.0 */
#include <libpldm/base.h>
#include <libpldm/byteorder.h>
#include <libpldm/edac.h>
#include <libpldm/platform.h>

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

_Static_assert(sizeof(struct pldm_msg_hdr) == 3, "PLDM header wire layout");
_Static_assert(sizeof(struct pldm_pdr_hdr) == 10, "PDR header wire layout");
_Static_assert(offsetof(struct pldm_pdr_hdr, length) == 8, "PDR length offset");

static int check_endian(void) {
  const unsigned char little[] = {0xef, 0xcd, 0xab, 0x89};
  const unsigned char big[] = {0x89, 0xab, 0xcd, 0xef};
  uint32_t le = htole32(UINT32_C(0x89abcdef));
  uint32_t be = htobe32(UINT32_C(0x89abcdef));
  uint64_t wide = UINT64_C(0x123456789abcdef0);

  return memcmp(&le, little, sizeof(le)) || memcmp(&be, big, sizeof(be)) ||
         le32toh(le) != UINT32_C(0x89abcdef) ||
         be32toh(be) != UINT32_C(0x89abcdef) ||
         le16toh(htole16(0x1234)) != 0x1234 ||
         be16toh(htobe16(0x1234)) != 0x1234 || le64toh(htole64(wide)) != wide ||
         be64toh(htobe64(wide)) != wide;
}

static int check_header(void) {
  const struct pldm_header_info info = {.msg_type = PLDM_REQUEST,
                                        .instance = 5,
                                        .pldm_type = PLDM_BASE,
                                        .command = PLDM_GET_PLDM_VERSION};
  const unsigned char expected[] = {0x85, 0x00, 0x03};
  struct pldm_msg_hdr header = {0};

  return pack_pldm_header(&info, &header) != PLDM_SUCCESS ||
         memcmp(&header, expected, sizeof(expected));
}

int main(void) {
  if (check_endian() || check_header() ||
      pldm_edac_crc32("123456789", 9) != UINT32_C(0xcbf43926)) {
    fputs("Installed C consumer failed\n", stderr);
    return 1;
  }
  puts("Installed C consumer: wire layout, endian, CRC and linkage OK");
  return 0;
}
