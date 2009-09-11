//
//	Copyright (c) 2008-2009, AppReviews
//	http://github.com/gambcl/AppReviews
//	http://www.perculasoft.com/appreviews
//	All rights reserved.
//
//	This software is released under the terms of the BSD License.
//	http://www.opensource.org/licenses/bsd-license.php
//
//	Redistribution and use in source and binary forms, with or without modification,
//	are permitted provided that the following conditions are met:
//
//	* Redistributions of source code must retain the above copyright notice, this
//	  list of conditions and the following disclaimer.
//	* Redistributions in binary form must reproduce the above copyright notice,
//	  this list of conditions and the following disclaimer
//	  in the documentation and/or other materials provided with the distribution.
//	* Neither the name of AppReviews nor the names of its contributors may be used
//	  to endorse or promote products derived from this software without specific
//	  prior written permission.
//
//	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//	ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//	WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//	IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//	INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//	BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//	DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
//	LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
//	OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
//	OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "ARAppIconDownloadOperation.h"
#import "ARAppStoreApplication.h"
#import "AppReviewsAppDelegate.h"
#import "PSLog.h"

NSString *kARAppIconDownloadOperationDidStartNotification = @"ARAppIconDownloadOperationDidStartNotification";
NSString *kARAppIconDownloadOperationDidFinishNotification = @"ARAppIconDownloadOperationDidFinishNotification";
NSString *kARAppIconDownloadOperationDidFailNotification = @"ARAppIconDownloadOperationDidFailNotification";

@interface ARAppIconDownloadOperation ()

@property (nonatomic, retain) NSMutableData *data;

- (void)createFinalIcon;
+ (CGImageRef)iconMask;
+ (UIImage *)iconOutline;

@end


@implementation ARAppIconDownloadOperation

@synthesize app;
@synthesize data;

- (id)initWithApplication:(ARAppStoreApplication *)anApp
{
	if (self = [super init])
	{
		app = [anApp retain];
	}
	
	return self;
}

- (void)dealloc
{
	[app release];
	[data release];
	
	[super dealloc];
}

- (void)main
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[[NSNotificationCenter defaultCenter]
	 performSelectorOnMainThread:@selector(postNotification:)
	 withObject:[NSNotification notificationWithName:kARAppIconDownloadOperationDidStartNotification
																						object:app]
	 waitUntilDone:YES];
	
	if (![self isCancelled])
	{
		NSURL *appIconURL = [NSURL URLWithString:app.appIconURL];
		data = [[NSMutableData alloc] init];
		
		NSMutableURLRequest *request =
			[NSMutableURLRequest requestWithURL:appIconURL
															cachePolicy:NSURLRequestUseProtocolCachePolicy
													timeoutInterval:10.0];
		[request setValue:@"iTunes/4.2 (Macintosh; U; PPC Mac OS X 10.2"
	 forHTTPHeaderField:@"User-Agent"];
		[request setValue:[NSString stringWithFormat:@" %@-1",
											 app.defaultStoreIdentifier]
	 forHTTPHeaderField:@"X-App-Store-Front"];
		
#ifdef DEBUG
		NSDictionary *headerFields = [request allHTTPHeaderFields];
		PSLogDebug([headerFields descriptionWithLocale:nil indent:2]);
#endif
		
		AppReviewsAppDelegate *appDelegate = [[UIApplication sharedApplication]
																					delegate];
		[appDelegate performSelectorOnMainThread:@selector(increaseNetworkUsageCount)
																	withObject:nil
															 waitUntilDone:YES];
		finished = NO;
		[NSURLConnection connectionWithRequest:request delegate:self];
		
		do
		{
			CFRunLoopRunInMode(kCFRunLoopDefaultMode,
												 0.25,
												 false); 
		} while(!finished);
	}
	
	[pool drain];
}

- (void)createFinalIcon
{
	UIImage *originalIcon = [[UIImage alloc] initWithData:data];
	CGSize size = CGSizeMake(29, 29);
	CGRect rect = CGRectMake(0, 0, 29, 29);
	UIGraphicsBeginImageContext(size);
	CGContextClipToMask(UIGraphicsGetCurrentContext(),
											rect,
											[[self class] iconMask]);
	[originalIcon drawInRect:rect];
	[[[self class] iconOutline] drawInRect:rect];
	UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	[originalIcon release];
	
	app.appIcon = result;
	
	[[NSNotificationCenter defaultCenter]
	 performSelectorOnMainThread:@selector(postNotification:)
	 withObject:[NSNotification notificationWithName:kARAppIconDownloadOperationDidFinishNotification
																						object:app]
	 waitUntilDone:YES];
}

+ (CGImageRef)iconMask {
	static CGImageRef _iconMask = NULL;
	
	@synchronized(self) {
		if (!_iconMask) {
			NSString *maskImagePath = [[[NSBundle mainBundle] resourcePath]
																 stringByAppendingPathComponent:@"iconmask.png"];
			UIImage *maskImage = [UIImage imageWithContentsOfFile:maskImagePath];
			CGImageRef maskImageRef = [maskImage CGImage];
			_iconMask = CGImageMaskCreate(CGImageGetWidth(maskImageRef),
																		CGImageGetHeight(maskImageRef),
																		CGImageGetBitsPerComponent(maskImageRef),
																		CGImageGetBitsPerPixel(maskImageRef),
																		CGImageGetBytesPerRow(maskImageRef),
																		CGImageGetDataProvider(maskImageRef),
																		NULL,
																		false);
		}
	}
	
	return _iconMask;
}

+ (UIImage *)iconOutline {
	static UIImage *_iconOutline = nil;
	
	@synchronized(self) {
		if (!_iconOutline) {
			NSString *outlineImagePath = [[[NSBundle mainBundle] resourcePath]
																		stringByAppendingPathComponent:@"iconoutline.png"];
			_iconOutline = [[UIImage alloc] initWithContentsOfFile:outlineImagePath];
		}
	}
	
	return _iconOutline;
}

#pragma mark -
#pragma mark NSURLConnection delegate methods

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)d
{
	if ([self isCancelled]) {
		[connection cancel];
		
		[[NSNotificationCenter defaultCenter]
		 performSelectorOnMainThread:@selector(postNotification:)
		 withObject:[NSNotification notificationWithName:kARAppIconDownloadOperationDidFailNotification
																							object:app]
		 waitUntilDone:YES];
		
		
		finished = YES;
		return;
	}
	
	[data appendData:d];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	if (![self isCancelled]) {
		[self createFinalIcon];
	}
	
	finished = YES;
}

- (void)connection:(NSURLConnection *)connection
	didFailWithError:(NSError *)error
{
	PSLogError(@"URL request failed with error:%@", error);
	
	[[NSNotificationCenter defaultCenter]
	 performSelectorOnMainThread:@selector(postNotification:)
	 withObject:[NSNotification notificationWithName:kARAppIconDownloadOperationDidFailNotification
																						object:app]
	 waitUntilDone:YES];	
	
	finished = YES;
}

@end
