#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface RMEBridge : NSObject
+ (NSDictionary<NSString *, id> *)readPath:(NSString *)path
                                 artwork:(BOOL)artwork NS_SWIFT_NAME(read(path:artwork:));
+ (NSDictionary<NSString *, id> *)writePath:(NSString *)path
                                   fields:(NSDictionary<NSString *, NSString *> *)fields
                                  artwork:(nullable NSData *)artwork
                            removeArtwork:(BOOL)remove NS_SWIFT_NAME(write(path:fields:artwork:removeArtwork:));
@end
NS_ASSUME_NONNULL_END
