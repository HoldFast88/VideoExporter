//
//  VideoExporter.h
//
//  Created by Alexey Voitenko on 17.09.15.
//  Copyright © 2015 Aleksey. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>


typedef void (^ExportCompletionHandler)(BOOL success, NSURL *movieURL);


@interface VideoExporter : NSObject

+ (instancetype)sharedExporter;
- (void)exportVideoAtURL:(NSURL *)videoURL
        withCIFilterName:(NSString *)filterName
    andCompletionHandler:(ExportCompletionHandler)completionHandler;
- (void)exportVideoAsset:(AVAsset *)videoAsset
        withCIFilterName:(NSString *)filterName
    andCompletionHandler:(ExportCompletionHandler)completionHandler;

@end
