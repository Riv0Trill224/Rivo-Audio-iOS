#import "RMEBridge.h"
#include "TagCore.hpp"
@implementation RMEBridge
+ (NSDictionary *)readPath:(NSString *)path artwork:(BOOL)artwork {
  try {
    auto m = Rivo::read(path.fileSystemRepresentation, artwork);
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for(const auto &[k,v] : m.fields) fields[@(k.c_str())] = @(v.c_str());
    return @{@"fields": fields, @"duration": @(m.duration), @"bitrate": @(m.bitrate),
             @"sampleRate": @(m.sampleRate), @"hasArtwork": @(m.hasArtwork),
             @"artwork": [NSData dataWithBytes:m.artwork.data() length:m.artwork.size()]};
  } catch(const std::exception &e) { return @{@"error": @(e.what())}; }
}
+ (NSDictionary *)writePath:(NSString *)path fields:(NSDictionary<NSString *, NSString *> *)fields
                    artwork:(NSData *)artwork removeArtwork:(BOOL)remove {
  try {
    std::map<std::string, std::string> patch;
    for(NSString *key in fields) patch[key.UTF8String] = fields[key].UTF8String;
    std::vector<unsigned char> bytes;
    if(artwork.length) {
      auto start = static_cast<const unsigned char *>(artwork.bytes);
      bytes.assign(start,start + artwork.length);
    }
    Rivo::write(path.fileSystemRepresentation, patch, artwork ? &bytes : nullptr, remove);
    return @{@"ok": @YES};
  } catch(const std::exception &e) { return @{@"error": @(e.what())}; }
}
@end
