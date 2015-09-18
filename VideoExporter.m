//
//  VideoExporter.m
//
//  Created by Alexey Voitenko on 17.09.15.
//  Copyright © 2015 Aleksey. All rights reserved.
//

#import "VideoExporter.h"
#import <CoreImage/CoreImage.h>
#import <GLKit/GLKit.h>
#import <MobileCoreServices/MobileCoreServices.h>


static CGColorSpaceRef sDeviceRgbColorSpace = NULL;
static CVPixelBufferRef renderedOutputPixelBufferForRecording = NULL;


@interface VideoExporter ()

@property (strong, nonatomic) CIContext *coreImageContext;
@property (nonatomic) CGContextRef cgContext;
@property (nonatomic) GLuint renderBuffer;
@property (strong, nonatomic) EAGLContext *context;
@property (strong, nonatomic) AVAssetReader *assetReader;
@property (strong, nonatomic) AVAssetWriter *assetWriter;
@property (strong, nonatomic) AVAssetWriterInputPixelBufferAdaptor *inputPixelBufferAdaptor;
@property (strong, nonatomic) AVAssetWriterInput *assetWriterVideoInput;

@end


@implementation VideoExporter

+ (instancetype)sharedExporter
{
    static VideoExporter *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    
    return instance;
}

- (void)exportVideoAtURL:(NSURL *)videoURL withCIFilterName:(NSString *)filterName andCompletionHandler:(ExportCompletionHandler)completionHandler
{
    [self exportVideoAsset:[AVAsset assetWithURL:videoURL] withCIFilterName:filterName andCompletionHandler:completionHandler];
}

- (void)exportVideoAsset:(AVAsset *)videoAsset withCIFilterName:(NSString *)filterName andCompletionHandler:(ExportCompletionHandler)completionHandler
{
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    self.coreImageContext = [CIContext contextWithEAGLContext:self.context];
    sDeviceRgbColorSpace = CGColorSpaceCreateDeviceRGB();
    
    glGenRenderbuffers(1, &_renderBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _renderBuffer);
    
    AVAssetTrack *videoTrack = [[videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    
    NSError *error = nil;
    self.assetReader = [AVAssetReader assetReaderWithAsset:videoAsset error:&error];
    NSParameterAssert(self.assetReader != nil);
    
    // Video
    NSDictionary *decompressionVideoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32ARGB), (id)kCVPixelBufferIOSurfacePropertiesKey : @{}};
    AVAssetReaderOutput *videoOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack outputSettings:decompressionVideoSettings];
    
    if ([self.assetReader canAddOutput:videoOutput]) {
        [self.assetReader addOutput:videoOutput];
    }
    
    NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"movie" stringByAppendingPathExtension:@"mov"]];
    NSURL *url = [NSURL fileURLWithPath:outputFilePath];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:outputFilePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:outputFilePath error:&error];
        NSParameterAssert(error == nil);
    }
    
    self.assetWriter = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeQuickTimeMovie error:&error];
    NSParameterAssert(error == nil);
    
    NSDictionary *videoCompressionSettings = @{AVVideoCodecKey : AVVideoCodecH264,
                                               AVVideoWidthKey : @(videoTrack.naturalSize.width),
                                               AVVideoHeightKey : @(videoTrack.naturalSize.height)};
    
    self.assetWriterVideoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoCompressionSettings];
    self.assetWriterVideoInput.transform = videoTrack.preferredTransform;
    self.assetWriterVideoInput.expectsMediaDataInRealTime = YES;
    
    if ([self.assetWriter canAddInput:self.assetWriterVideoInput]) {
        [self.assetWriter addInput:self.assetWriterVideoInput];
    }
    
    NSDictionary *pixelBufferAttributes = @{
                                            (id)kCVPixelBufferCGImageCompatibilityKey : @(YES),
                                            (id)kCVPixelBufferCGBitmapContextCompatibilityKey : @(YES),
                                            (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32ARGB)
                                            };
    self.inputPixelBufferAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.assetWriterVideoInput sourcePixelBufferAttributes:pixelBufferAttributes];
    
    [self.assetReader startReading];
    
    [self.assetWriter startWriting];
    [self.assetWriter startSessionAtSourceTime:kCMTimeZero];
    
    [self.assetWriterVideoInput requestMediaDataWhenReadyOnQueue:dispatch_get_main_queue() usingBlock:^{
        while ([self.assetWriterVideoInput isReadyForMoreMediaData]) {
            CMSampleBufferRef videoSampleBuffer = [videoOutput copyNextSampleBuffer];
            
            if (videoSampleBuffer == NULL) {
                break;
            }
            
            CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(videoSampleBuffer);
            CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(videoSampleBuffer);
            
            CIImage *sourceImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
            CIImage *finalImage = sourceImage;
            
            if (filterName != nil) {
                CIFilter *filter = [CIFilter filterWithName:filterName];
                [filter setValue:sourceImage forKey:kCIInputImageKey];
                
                finalImage = filter.outputImage;
            }
            
            if (renderedOutputPixelBufferForRecording == NULL) {
                OSStatus err = CVPixelBufferPoolCreatePixelBuffer(nil, self.inputPixelBufferAdaptor.pixelBufferPool, &renderedOutputPixelBufferForRecording);
                
                if (err) {
                    NSLog(@"Cannot obtain a pixel buffer from the buffer pool");
                    return;
                }
            }
            
            if (finalImage) {
                [self.coreImageContext render:finalImage toCVPixelBuffer:renderedOutputPixelBufferForRecording bounds:[finalImage extent] colorSpace:sDeviceRgbColorSpace];
            }
            
            [self.inputPixelBufferAdaptor appendPixelBuffer:renderedOutputPixelBufferForRecording withPresentationTime:timestamp];
            
            CFRelease(videoSampleBuffer);
            videoSampleBuffer = NULL;
            
            [NSThread sleepForTimeInterval:0.01f]; // Not good, but it works, if sleep time set to 0 it will be video artefacts
        }
        
        [self.assetWriterVideoInput markAsFinished];
        [self.assetReader cancelReading];
        
        [self.assetWriter finishWritingWithCompletionHandler:^{
            if (self.assetWriter.status == AVAssetWriterStatusCompleted) {
                [self createAssetWithVideoTrackFromAsset:[AVAsset assetWithURL:self.assetWriter.outputURL] audioTrackFromAsset:videoAsset andCompletionHandler:^(BOOL success, NSURL *movieURL) {
                    if (completionHandler) {
                        completionHandler(self.assetWriter.status == AVAssetWriterStatusCompleted && success, movieURL);
                    }
                }];
            } else {
                if (completionHandler) {
                    completionHandler(NO, nil);
                }
            }
        }];
    }];
}

#pragma mark - Private

- (void)createAssetWithVideoTrackFromAsset:(AVAsset *)videoAsset audioTrackFromAsset:(AVAsset *)audioAsset andCompletionHandler:(ExportCompletionHandler)completionHandler
{
    AVAssetTrack *assetVideoTrack = [[videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    AVAssetTrack *assetAudioTrack = [[audioAsset tracksWithMediaType:AVMediaTypeAudio] firstObject];
    
    AVMutableComposition *composition = [AVMutableComposition composition];
    
    AVMutableCompositionTrack *videoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *audioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    
    NSError *error = nil;
    [videoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoAsset.duration) ofTrack:assetVideoTrack atTime:kCMTimeZero error:&error];
    NSParameterAssert(error == nil);
    [audioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, audioAsset.duration) ofTrack:assetAudioTrack atTime:kCMTimeZero error:&error];
    NSParameterAssert(error == nil);
    
    NSURL *outputURL = [[[[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil] URLByAppendingPathComponent:@"passthrought"] URLByAppendingPathExtension:CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)AVFileTypeQuickTimeMovie, kUTTagClassFilenameExtension))];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[outputURL path]]) {
        [[NSFileManager defaultManager] removeItemAtURL:outputURL error:&error];
        NSParameterAssert(error == nil);
    }
    
    AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetPassthrough];
    exporter.outputURL = outputURL;
    exporter.outputFileType = AVFileTypeQuickTimeMovie;
    exporter.shouldOptimizeForNetworkUse = NO;
    
    [exporter exportAsynchronouslyWithCompletionHandler:^{
        if (completionHandler) {
            completionHandler(exporter.error == nil, exporter.outputURL);
        }
    }];
}

@end
