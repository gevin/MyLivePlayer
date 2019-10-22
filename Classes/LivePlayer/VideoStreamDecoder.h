//
//  VideoStreamDecoder.h
//  MyLivePlayer
//
//  Created by GevinChen on 19/8/24.
//  Copyright (c) 2019年 GevinChen. All rights reserved.

#import <Foundation/Foundation.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#import "GLESView.h"
#import "AudioStreamDecoder.h"

@interface VideoStreamDecoder : NSObject
{
    
}

@property (nonatomic) NSTimeInterval startTime;

@property (nonatomic, readonly) GLESView* glView;

@property (nonatomic, assign) AudioStreamDecoder *audioDecoder; 

- (int)setupWithAVStream:(AVStream *) pAVStream;

- (NSUInteger)packetCount;

- (void)putPacket:(AVPacket*)avpacket;

- (void)setVolume:(float)volume;

- (int)isRunning;

- (void)start;

- (void)stop;

- (void)destroy;

@end
