#import "EPMultipartURLPoster.h"

// =============================================================================

@interface NSStream (BoundPairAdditions)

+ (void)createBoundInputStream:(NSInputStream**)inputStreamPtr outputStream:(NSOutputStream**)outputStreamPtr bufferSize:(NSUInteger)bufferSize;

@end

@implementation NSStream (BoundPairAdditions)

+ (void)createBoundInputStream:(NSInputStream**)inputStreamPtr outputStream:(NSOutputStream**)outputStreamPtr bufferSize:(NSUInteger)bufferSize
{
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    
    CFStreamCreateBoundPair(NULL,
                            inputStreamPtr ? &readStream : NULL,
                            outputStreamPtr ? &writeStream : NULL,
                            bufferSize);
    
    if (inputStreamPtr) {
        *inputStreamPtr = CFBridgingRelease(readStream);
    }
    
    if (outputStreamPtr) {
        *outputStreamPtr = CFBridgingRelease(writeStream);
    }
}

@end

// =============================================================================

#define kPreambleStringFormat @"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n"
#define kPreambleDataFormat @"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\nContent-Type: %@\r\n\r\n"
#define kPreamblePathFormat @"--%@\r\nContent-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\nContent-Type: %@\r\n\r\n"
#define kEndFormat @"--%@--\r\n"

#define BUFFER_SIZE 32768

static NSString *MIMETypeForExtension(NSString *extension)
{
    CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)extension, NULL);
    if (uti != NULL) {
        CFStringRef mime = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType);
        CFRelease(uti);
        if (mime != NULL) {
            NSString *type = [NSString stringWithString:(__bridge NSString*)mime];
            CFRelease(mime);
            return type;
        }
    }
    return @"application/octet-stream";
}

// =============================================================================

@interface EPMultipartPart ()

@property (nonatomic) NSUInteger length;
@property (nonatomic) NSUInteger bytesLeft;

- (NSData*)getNextDataChunk;

@end

@implementation EPMultipartPart {
    NSData *_headers;
    NSInputStream *_body;
    NSUInteger _headersLength;
    NSUInteger _bodyLength;
}

- (void)updateLength
{
    _length = _headersLength + _bodyLength + 2;
    _bytesLeft = _length;
    [_body open];
}

- (instancetype)initWithName:(NSString*)name boundary:(NSString*)boundary string:(NSString*)string
{
    self = [super init];
    if (self) {
        _headers = [[NSString stringWithFormat:kPreambleStringFormat, boundary, name] dataUsingEncoding:NSUTF8StringEncoding];
        _headersLength = [_headers length];
        NSData *stringData = [string dataUsingEncoding:NSUTF8StringEncoding];
        _body = [NSInputStream inputStreamWithData:stringData];
        _bodyLength = stringData.length;
        [self updateLength];
    }
    return self;
}

- (instancetype)initWithName:(NSString*)name boundary:(NSString*)boundary data:(NSData*)data contentType:(NSString*)contentType
{
    self = [super init];
    if (self) {
        _headers = [[NSString stringWithFormat:kPreambleDataFormat, boundary, name, contentType] dataUsingEncoding:NSUTF8StringEncoding];
        _headersLength = [_headers length];
        _body = [NSInputStream inputStreamWithData:data];
        _bodyLength = [data length];
        [self updateLength];
    }
    return self;
}

- (instancetype)initWithName:(NSString*)name boundary:(NSString*)boundary data:(NSData*)data contentType:(NSString*)contentType filename:(NSString*)filename
{
    self = [super init];
    if (self) {
        _headers = [[NSString stringWithFormat:kPreamblePathFormat, boundary, name, filename, contentType] dataUsingEncoding:NSUTF8StringEncoding];
        _headersLength = [_headers length];
        _body = [NSInputStream inputStreamWithData:data];
        _bodyLength = [data length];
        [self updateLength];
    }
    return self;
}

- (instancetype)initWithName:(NSString*)name filename:(NSString*)filename boundary:(NSString*)boundary path:(NSString*)path
{
    self = [super init];
    if (self) {
        if (!filename) {
            filename = path.lastPathComponent;
        }
        _headers = [[NSString stringWithFormat:kPreamblePathFormat, boundary, name, filename, MIMETypeForExtension(path.pathExtension)] dataUsingEncoding:NSUTF8StringEncoding];
        _headersLength = [_headers length];
        _body = [NSInputStream inputStreamWithFileAtPath:path];
        _bodyLength = [[[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] objectForKey:NSFileSize] unsignedIntegerValue];
        [self updateLength];
    }
    return self;
}

- (instancetype)initWithName:(NSString*)name filename:(NSString*)filename boundary:(NSString *)boundary stream:(NSInputStream*)stream streamLength:(NSUInteger)streamLength
{
    self = [super init];
    if (self) {
        _headers = [[NSString stringWithFormat:kPreamblePathFormat, boundary, name, filename, MIMETypeForExtension(filename.pathExtension)] dataUsingEncoding:NSUTF8StringEncoding];
        _headersLength = [_headers length];
        _body = stream;
        _bodyLength = streamLength;
        [self updateLength];
    }
    return self;
}

- (NSData*)getNextDataChunk
{
    if (_headers) {
        NSData *returnData = _headers;
        _headers = nil;
        _bytesLeft -= [returnData length];
        return returnData;
    }
    unsigned char *buffer = malloc(BUFFER_SIZE+2);
    NSInteger readLength = [_body read:buffer maxLength:BUFFER_SIZE];
    if (readLength >= 0) {
        if (![_body hasBytesAvailable] || readLength == 0) { // hasBytesAvailable doesn't seem to work so added readLength check
            memcpy((char*)&buffer[readLength], "\r\n", 2);
            readLength += 2;
        }
        _bytesLeft -= readLength;
        return [NSData dataWithBytesNoCopy:buffer length:readLength freeWhenDone:YES];
    }
    return nil;
}

@end

// =============================================================================

@implementation EPMultipartURLPoster {
    NSURL *_url;
    NSMutableArray *_parts;
    NSOutputStream *_producerStream;
    NSInputStream *_consumerStream;
    NSData *_nextData;
    NSData *_endData;
}

- (instancetype)initWithURL:(NSURL*)url
{
    self = [super init];
    if (self) {
        _url = url;
        _parts = [NSMutableArray array];
        _boundary = [[NSProcessInfo processInfo] globallyUniqueString];
        _endData = [[NSString stringWithFormat:kEndFormat, _boundary] dataUsingEncoding:NSUTF8StringEncoding];
    }
    return self;
}

- (NSUInteger)totalLength
{
    NSUInteger totalLength = 0;
    
    for (EPMultipartPart *part in _parts) {
        totalLength += part.length;
    }
    
    totalLength += [_endData length];
    
    return totalLength;
}

- (void)addPart:(EPMultipartPart*)part
{
    [_parts addObject:part];
}

- (void)start
{
    NSInputStream *consStream;
    NSOutputStream *prodStream;
    
    [NSStream createBoundInputStream:&consStream outputStream:&prodStream bufferSize:BUFFER_SIZE];
    
    _consumerStream = consStream;
    _producerStream = prodStream;
    
    _producerStream.delegate = self;
    [_producerStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [_producerStream open];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:_url];
    
    [request setHTTPMethod:@"POST"];
    [request setHTTPBodyStream:_consumerStream];
    
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=\"%@\"", _boundary] forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[self totalLength]] forHTTPHeaderField:@"Content-Length"];
    
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [connection start];
}

- (void)stop
{
    if (_producerStream) {
        _producerStream.delegate = nil;
        [_producerStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [_producerStream close];
        _producerStream = nil;
    }
    _consumerStream = nil;
    [_parts removeAllObjects];
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode) {
            
        case NSStreamEventOpenCompleted:
            break;
            
        case NSStreamEventHasBytesAvailable:
            break;
            
        case NSStreamEventHasSpaceAvailable:
        {
            EPMultipartPart *part = [_parts firstObject];
            
            if (part || _nextData) {
                
                if (part) {
                    if (!_nextData) {
                        _nextData = [part getNextDataChunk];
                    }
                    
                    if ([part bytesLeft] == 0) {
                        [_parts removeObject:part];
                    }
                }
                
                if (_nextData) {
                    NSInteger length = _nextData.length;
                    NSInteger bytesWritten;
                    bytesWritten = [_producerStream write:_nextData.bytes maxLength:length];
                    if (bytesWritten <= 0) {
                        [self stop];
                        return;
                    } else if (bytesWritten < length) {
                        _nextData = [_nextData subdataWithRange:NSMakeRange(bytesWritten, length-bytesWritten)];
                    } else {
                        _nextData = nil;
                    }
                }
                
                if (!_nextData && !_parts.count) {
                    if (_endData) {
                        _nextData = _endData;
                        _endData = nil;
                    } else {
                        // All done!
                        [self stop];
                    }
                }
                
            } else {
                _producerStream.delegate = nil;
                [_producerStream close];
            }
            
        }
            break;
            
        case NSStreamEventErrorOccurred:
            [self stop];
            break;
            
        case NSStreamEventEndEncountered:
            break;
            
        default:
            break;
    }
}

- (void)connection:(NSURLConnection*)connection didFailWithError:(NSError*)error
{
    if (_delegate) {
        [_delegate connection:connection didFailWithError:error];
    }
}

- (void)connection:(NSURLConnection*)connection didReceiveResponse:(NSURLResponse*)response
{
    if (_delegate) {
        [_delegate connection:connection didReceiveResponse:response];
    }
}

- (void)connection:(NSURLConnection*)connection
   didSendBodyData:(NSInteger)bytesWritten
 totalBytesWritten:(NSInteger)totalBytesWritten
totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    if (_delegate) {
        [_delegate connection:connection
              didSendBodyData:bytesWritten
            totalBytesWritten:totalBytesWritten
    totalBytesExpectedToWrite:totalBytesExpectedToWrite];
    }
}

@end
