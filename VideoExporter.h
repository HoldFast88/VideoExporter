//
//  VideoExporter.h
//
//  Created by Alexey Voitenko on 17.09.15.
//  Copyright © 2015 Aleksey. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef void (^ExportCompletionHandler)(BOOL success, NSURL *movieURL);


@interface VideoExporter : NSObject

+ (instancetype)sharedExporter;
- (void)exportVideoAtURL:(NSURL *)videoURL
        withCIFilterName:(NSString *)filterName
    andCompletionHandler:(ExportCompletionHandler)completionHandler;

@end
