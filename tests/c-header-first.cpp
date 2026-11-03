/* SPDX-License-Identifier: Apache-2.0 */
/* Do not pre-include C++ headers: libc++ must see C++ linkage on first use. */
extern "C" {
#include <libpldm/base.h>
}

#include <cstddef>
#include <type_traits>

static_assert(sizeof(pldm_msg_hdr) == 3, "PLDM header wire layout");
static_assert(std::is_same_v<decltype(variable_field::length), std::size_t>);

int main() {
  const pldm_header_info info = {.msg_type = PLDM_REQUEST,
                                 .instance = 5,
                                 .pldm_type = PLDM_BASE,
                                 .command = PLDM_GET_PLDM_VERSION,
                                 .completion_code = PLDM_SUCCESS};
  pldm_msg_hdr header = {};

  return pack_pldm_header(&info, &header) != PLDM_SUCCESS ||
         header.request != 1 || header.instance_id != 5 ||
         header.type != PLDM_BASE || header.command != PLDM_GET_PLDM_VERSION;
}
