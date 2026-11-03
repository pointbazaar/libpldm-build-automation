/* SPDX-License-Identifier: Apache-2.0 */
#include <libpldm/byteorder.h>
#include <libpldm/edac.h>
#include <libpldm/firmware_update.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* DSP0267 FR02H: one component (id 100), byte image 0x1a, no devices.
 * Contains a Windows text-mode EOF byte to check pd's binary stdin.
 */
int main(int argc, char **argv) {
  const uint8_t identifier[] = PLDM_PACKAGE_HEADER_IDENTIFIER_V1_1;
  uint8_t package[69] = {0};
  uint32_t checksum;
  FILE *output;

  if (argc != 2) {
    return 1;
  }
  memcpy(package, identifier, sizeof(identifier));
  package[16] = 2;
  package[17] = 68;
  package[32] = 8;
  package[34] = 1;
  package[35] = 1;
  package[36] = 'v';
  package[39] = 1;
  package[41] = 10;
  package[43] = 100;
  memset(package + 45, 0xff, 4);
  package[53] = 68;
  package[57] = 1;
  package[61] = 1;
  package[62] = 1;
  package[63] = 'v';
  checksum = htole32(pldm_edac_crc32(package, 64));
  memcpy(package + 64, &checksum, sizeof(checksum));
  package[68] = 0x1a;
  output = fopen(argv[1], "wb");
  if (!output) {
    return 1;
  }
  if (fwrite(package, 1, sizeof(package), output) != sizeof(package)) {
    fclose(output);
    return 1;
  }
  return fclose(output) != 0;
}
