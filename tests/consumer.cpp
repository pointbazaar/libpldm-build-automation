/* SPDX-License-Identifier: Apache-2.0 */
#include <libpldm++/firmware_update.hpp>

#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>

int main(int argc, char **argv) {
  if (argc != 2) {
    return 1;
  }
  std::ifstream input(argv[1], std::ios::binary);
  if (!input) {
    return 1;
  }
  const std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)),
                                   std::istreambuf_iterator<char>());
  auto parsed = pldm::fw_update::PackageParser::parse(
      bytes, pldm::fw_update::PackagePin::v1_1_0);
  if (!parsed) {
    std::cerr << parsed.error().msg << '\n';
    return 1;
  }
  const auto &components = (*parsed)->componentImageInformation;
  if (components.size() != 1 || components[0].componentIdentifier != 100 ||
      components[0].componentVersion != "v" ||
      components[0].componentLocation.length != 1 ||
      *components[0].componentLocation.ptr != 0x1a) {
    return 1;
  }
  std::cout << "Installed C++ consumer: package parser and linkage OK\n";
  return 0;
}
