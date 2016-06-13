#EPMultipartHTTPPoster

Was looking into posting some http multipart messages but couldn't find a safe solution.

First looked at [PKMultipartInputStream](https://github.com/pyke369/PKMultipartInputStream) but this seem to rely on a hack.
The full hack is described here [Subclassing NSInputStream](http://bjhomer.blogspot.se/2011/04/subclassing-nsinputstream.html).

But Apple had some sample code that gave a hint of a safer way, see [SimpleURLConnections](https://developer.apple.com/library/ios/samplecode/SimpleURLConnections).

This is more or less a mix of PKMultipartInputStream and the sample code.

Not fully tested.

Usage
=====

    EPMultipartHTTPPoster *multipartHTTPPoster = [[EPMultipartHTTPPoster alloc] initWithURL:[NSURL URLWithString:@"http://site.com/upload-file-script"]];
    multipartHTTPPoster.delegate = self;
    [multipartHTTPPoster addPart:[[EPMultipartHTTPPart alloc] initWithName:@"upload-name"
                                                                  filename:nil
                                                                  boundary:multipartHTTPPoster.boundary
                                                                      path:@"/some/file/path.ext"]];
    [multipartHTTPPoster start];

License
=======

This code is distributed under the terms and conditions of the [MIT license](License.md).
