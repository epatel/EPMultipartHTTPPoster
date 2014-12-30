#import <Foundation/Foundation.h>

// =============================================================================

@interface EPMultipartHTTPPart : NSObject

- (instancetype)initWithName:(NSString*)name boundary:(NSString*)boundary string:(NSString*)string;
- (instancetype)initWithName:(NSString*)name boundary:(NSString*)boundary data:(NSData*)data contentType:(NSString*)contentType;
- (instancetype)initWithName:(NSString*)name boundary:(NSString*)boundary data:(NSData*)data contentType:(NSString*)contentType filename:(NSString*)filename;
- (instancetype)initWithName:(NSString*)name filename:(NSString*)filename boundary:(NSString*)boundary path:(NSString*)path;
- (instancetype)initWithName:(NSString*)name filename:(NSString*)filename boundary:(NSString *)boundary stream:(NSInputStream*)stream streamLength:(NSUInteger)streamLength;

@end

// =============================================================================

@interface EPMultipartHTTPPoster : NSObject <NSStreamDelegate>

@property (nonatomic, readonly) NSString *boundary;
@property (nonatomic, weak) id delegate;

- (instancetype)initWithURL:(NSURL*)url;
- (void)addPart:(EPMultipartHTTPPart*)part;
- (void)start;

@end
