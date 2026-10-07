#include "TagCore.hpp"
#include <taglib/fileref.h>
#include <taglib/tpropertymap.h>
#include <taglib/tvariant.h>
#include <taglib/mp4file.h>
#include <taglib/mp4tag.h>
#include <taglib/mp4item.h>
#include <taglib/mpegfile.h>
#include <taglib/id3v2tag.h>
#include <taglib/synchronizedlyricsframe.h>
#include <cstdio>
#include <stdexcept>
#include <algorithm>

namespace {
TagLib::String str(const std::string &s) { return TagLib::String(s, TagLib::String::UTF8); }
std::string utf8(const TagLib::String &s) { return s.to8Bit(true); }
void validate(TagLib::FileRef &f) {
  if(f.isNull() || !f.file() || !f.file()->isValid() || !f.tag())
    throw std::runtime_error("Archivo no reconocido o dañado. No se ha modificado.");
  // MPEG files with an ID3 header but no audio frames can still report isValid().
  const auto ap = f.audioProperties();
  if(!ap || ap->sampleRate() <= 0 || ap->channels() <= 0)
    throw std::runtime_error("No se encontraron datos de audio válidos. No se ha modificado.");
}
const std::vector<std::string> keys = {
  "TITLE", "ARTIST", "ALBUM", "ALBUMARTIST", "DATE", "GENRE",
  "TRACKNUMBER", "DISCNUMBER", "COMPOSER", "COMMENT", "ISRC",
  "LYRICS", "MUSICBRAINZ_TRACKID", "MUSICBRAINZ_ALBUMID", "ITUNESADVISORY"
};
std::string get(const TagLib::PropertyMap &p, const std::string &key) {
  const auto k = str(key);
  return p.contains(k) && !p[k].isEmpty() ? utf8(p[k].front()) : "";
}
}

Rivo::Metadata Rivo::read(const std::string &path, bool includeArtwork) {
  TagLib::FileRef file(path.c_str(), true, TagLib::AudioProperties::Average);
  validate(file);
  Metadata result;
  result.hasArtwork = file.complexPropertyKeys().contains("PICTURE");
  const auto props = file.properties();
  for(const auto &k : keys) result.fields[k] = get(props, k);
  for(const auto &entry : props) {
    const auto key = utf8(entry.first);
    if(key == "LYRICS" || key.rfind("LYRICS:", 0) == 0) {
      for(const auto &value : entry.second) {
        if(!value.stripWhiteSpace().isEmpty()) {
          result.hasEmbeddedLyrics = true;
          if(result.fields["LYRICS"].empty()) result.fields["LYRICS"] = utf8(value);
        }
      }
    }
  }
  if(auto mpeg = dynamic_cast<TagLib::MPEG::File *>(file.file())) {
    if(auto tag = mpeg->ID3v2Tag(false)) {
      for(auto raw : tag->frameList("SYLT")) {
        auto lyrics = dynamic_cast<TagLib::ID3v2::SynchronizedLyricsFrame *>(raw);
        if(!lyrics || lyrics->type() != TagLib::ID3v2::SynchronizedLyricsFrame::Lyrics || lyrics->synchedText().isEmpty()) continue;
        result.hasEmbeddedLyrics = true;
        // MPEG-frame timestamps cannot be treated as milliseconds.
        if(lyrics->timestampFormat() != TagLib::ID3v2::SynchronizedLyricsFrame::AbsoluteMilliseconds || !result.embeddedSyncedLyrics.empty()) continue;
        for(const auto &line : lyrics->synchedText()) {
          if(line.text.stripWhiteSpace().isEmpty()) continue;
          char stamp[40];
          std::snprintf(stamp, sizeof(stamp), "[%02u:%02u.%03u]", line.time / 60000, (line.time / 1000) % 60, line.time % 1000);
          auto text = utf8(line.text);
          std::replace(text.begin(), text.end(), '\n', ' ');
          std::replace(text.begin(), text.end(), '\r', ' ');
          result.embeddedSyncedLyrics += std::string(stamp) + text + "\n";
        }
      }
    }
  }
  if(auto mp4 = dynamic_cast<TagLib::MP4::File *>(file.file())) {
    result.hasArtwork = !mp4->tag()->item("covr").toCoverArtList().isEmpty();
    if(mp4->tag()->contains("rtng")) {
      int rating = mp4->tag()->item("rtng").toByte();
      if(rating == 4) rating = 1; // Legacy Apple explicit value.
      result.fields["ITUNESADVISORY"] = std::to_string(rating);
    }
  }
  if(auto ap = file.audioProperties()) {
    result.duration = ap->lengthInMilliseconds() / 1000.0;
    result.bitrate = ap->bitrate(); result.sampleRate = ap->sampleRate();
  }
  if(includeArtwork) {
    auto pictures = file.complexProperties("PICTURE");
    for(const auto &picture : pictures) {
      auto data = picture.value("data").toByteVector();
      if(data.size() > 20 * 1024 * 1024) continue;
      bool front = picture.value("pictureType").toString() == "Front Cover";
      if(result.artwork.empty() || front)
        result.artwork.assign(data.begin(), data.end());
      if(front) break;
    }
  }
  return result;
}

void Rivo::write(const std::string &path,
                 const std::map<std::string, std::string> &patch,
                 const std::vector<unsigned char> *artwork, bool removeArtwork) {
  TagLib::FileRef file(path.c_str(), true, TagLib::AudioProperties::Average);
  validate(file);
  if(file.file()->readOnly()) throw std::runtime_error("El proveedor no permite escribir este archivo.");
  auto props = file.properties();
  auto mp4 = dynamic_cast<TagLib::MP4::File *>(file.file());
  for(const auto &[key,value] : patch) {
    if(std::find(keys.begin(),keys.end(),key) == keys.end())
      throw std::runtime_error("Campo no permitido: " + key);
    if(key == "ITUNESADVISORY" && mp4) continue;
    if(key == "ITUNESADVISORY" && value != "" && value != "0" && value != "1" && value != "2")
      throw std::runtime_error("Clasificación explícita inválida.");
    props.erase(str(key));
    if(!value.empty() && !(key == "ITUNESADVISORY" && value == "0"))
      props.insert(str(key), TagLib::StringList(str(value)));
  }
  const auto unsupported = file.setProperties(props);
  for(const auto &[key,value] : patch) {
    if(mp4 && key == "ITUNESADVISORY") continue;
    if(!value.empty() && unsupported.contains(str(key)))
      throw std::runtime_error("El formato no admite el campo: " + key);
  }
  if(mp4 && patch.count("ITUNESADVISORY")) {
    const auto &rating = patch.at("ITUNESADVISORY");
    if(rating.empty() || rating == "0") mp4->tag()->removeItem("rtng");
    else if(rating == "1" || rating == "2")
      mp4->tag()->setItem("rtng", TagLib::MP4::Item(static_cast<unsigned char>(std::stoi(rating))));
    else throw std::runtime_error("Clasificación explícita inválida.");
  }
  if(artwork || removeArtwork) {
    auto pictures = file.complexProperties("PICTURE");
    TagLib::List<TagLib::VariantMap> kept;
    unsigned int index = 0;
    for(const auto &pic : pictures) {
      const auto type = pic.value("pictureType").toString();
      // MP4 covr does not store a picture type. Its first image is the primary cover.
      if(type != "Front Cover" && !(type.isEmpty() && index == 0)) kept.append(pic);
      ++index;
    }
    if(artwork) {
      if(artwork->empty() || artwork->size() > 20 * 1024 * 1024)
        throw std::runtime_error("Portada vacía o demasiado grande.");
      TagLib::VariantMap pic;
      pic.insert("data", TagLib::ByteVector(reinterpret_cast<const char *>(artwork->data()), static_cast<unsigned int>(artwork->size())));
      pic.insert("description", str("Rivo front cover"));
      pic.insert("pictureType", str("Front Cover"));
      pic.insert("mimeType", str(artwork->at(0) == 0x89 ? "image/png" : "image/jpeg"));
      kept.prepend(pic);
    }
    if(!file.setComplexProperties("PICTURE", kept))
      throw std::runtime_error("Este formato no admite la portada solicitada.");
  }
  if(!file.save()) throw std::runtime_error("No fue posible guardar las etiquetas.");
}
