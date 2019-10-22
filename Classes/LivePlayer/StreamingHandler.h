//
//  StreamingHandler.h
//  MyLivePlayer
//
//  Created by GevinChen on 19/7/12.
//  Copyright (c) 2019年 GevinChen. All rights reserved.


#import <Foundation/Foundation.h>
#import "GLESView.h"
#import "AudioStreamDecoder.h"
#import "VideoStreamDecoder.h"
#import "AudioStreamALDecoder.h"

@protocol VideoExtractorDelegate <NSObject>

- (void)videoStart;

- (void)videoEnd;

@end

@interface StreamingHandler : NSObject {

}

@property (nonatomic, weak) id delegate; 

@property (nonatomic, readonly) CGSize sourceSize;

@property (nonatomic, readonly) GLESView* glView;

@property (nonatomic, readonly) AudioStreamDecoder* audioDecoder;

@property (nonatomic, readonly) VideoStreamDecoder* videoDecoder;

@property (nonatomic, readonly) BOOL isPlaying;

@property (nonatomic) NSString *videoPath;

-(void)destroy;

- (void)start;

- (void)stop;


@end
