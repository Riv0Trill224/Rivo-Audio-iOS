#include "TagCore.hpp"
#include <iostream>
#include <fstream>
#include <iterator>
int main(int argc, char **argv) {
  try {
    if(argc < 3) return 2;
    const std::string command = argv[1];
    if(command == "read") {
      auto m = Rivo::read(argv[2]);
      for(const auto &[k,v] : m.fields) std::cout << k << "\t" << v << "\n";
      std::cout << "DURATION\t" << m.duration << "\nARTWORK_BYTES\t" << m.artwork.size() << "\n";
    } else if(command == "edit" && argc >= 5) {
      std::ifstream f(argv[3],std::ios::binary);
      std::vector<unsigned char> cover((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
      Rivo::write(argv[2], {{"TITLE", "Canción de prueba Ø"}, {"ARTIST", "$uicideboy$"},
                           {"ALBUM", "Álbum de prueba"}, {"ALBUMARTIST", "RIVØ"}, {"DATE", "2026"},
                           {"GENRE", "Hip-Hop"}, {"TRACKNUMBER", "2/12"}, {"DISCNUMBER", "1/2"},
                           {"COMPOSER", "Said"}, {"ITUNESADVISORY",argv[4]}}, &cover, false);
    } else if(command == "rating" && argc >= 4) {
      Rivo::write(argv[2],{{"ITUNESADVISORY",argv[3]}},nullptr,false);
    } else if(command == "remove-cover") {
      Rivo::write(argv[2],{},nullptr,true);
    } else if(command == "erase") {
      Rivo::write(argv[2],{{"TITLE",""}},nullptr,false);
    } else return 2;
    return 0;
  } catch(const std::exception &e) { std::cerr << e.what() << "\n"; return 1; }
}
