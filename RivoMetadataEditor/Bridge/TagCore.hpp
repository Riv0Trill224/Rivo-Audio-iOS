#pragma once
#include <map>
#include <string>
#include <vector>

namespace Rivo {
struct Metadata {
  std::map<std::string, std::string> fields;
  std::vector<unsigned char> artwork;
  double duration = 0;
  int bitrate = 0;
  int sampleRate = 0;
  bool hasArtwork = false;
};
Metadata read(const std::string &path, bool artwork = true);
// Call only on a staging copy. The Swift file service verifies and commits it.
void write(const std::string &path,
           const std::map<std::string, std::string> &patch,
           const std::vector<unsigned char> *artwork, bool removeArtwork);
}
