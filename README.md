#EPMultipartURLPoster
=====================

Was looking into posting some http multipart messages but couldn't find a safe solution.

First looked at [PKMultipartInputStream](https://github.com/pyke369/PKMultipartInputStream) but this seem to rely on a hack.
The full hack is described here [Subclassing NSInputStream](http://bjhomer.blogspot.se/2011/04/subclassing-nsinputstream.html).

But Apple had some sample code that gave a hint of a safer way, see [SimpleURLConnections](https://developer.apple.com/library/ios/samplecode/SimpleURLConnections).

This is more or less a mix of PKMultipartInputStream and the sample code.

Not fully tested.

Usage
=====

    EPMultipartURLPoster *multipartURLPoster = [[EPMultipartURLPoster alloc] initWithURL:[NSURL URLWithString:@"http://site.com/upload-file-script"]];
    multipartURLPoster.delegate = self;
    [multipartURLPoster addPart:[[EPMultipartPart alloc] initWithName:@"upload-name"
                                                             filename:nil
                                                             boundary:multipartURLPoster.boundary
                                                                 path:@"/some/file/path.ext"]];
    [multipartURLPoster start];
