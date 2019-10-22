//
//  AudioStreamDecoder.h
//  MyLivePlayer
//
//  Created by GevinChen on 19/8/22.
//  Copyright (c) 2019年 GevinChen. All rights reserved.

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>


NS_ASSUME_NONNULL_BEGIN

enum HandlerStatus {
    handler_running = 1,
    handler_pause = 2,
    handler_stop = 3
}HandlerStatus;

@interface AudioStreamDecoder : NSObject
{
    
}

@property (nonatomic) NSTimeInterval startTime;

- (int)setupWithAVStream:(AVStream *) pAVStream;

- (NSUInteger)packetCount;

- (void)putPacket:(AVPacket*)avpacket;

- (BOOL)isQueueRunning;

- (void)setVolume:(float)volume;

- (int)state;

- (void)start;

- (void)stop;

- (void)destroy;

- (NSTimeInterval)getAudioStreamingTime;

@end

NS_ASSUME_NONNULL_END
