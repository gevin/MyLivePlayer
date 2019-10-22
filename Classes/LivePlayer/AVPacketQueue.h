//
//  AudioStreamingDataQueue.h
//  MyLivePlayer
//
//  Created by GevinChen on 19/8/22.
//  Copyright (c) 2019年 GevinChen. All rights reserved.

#import <Foundation/Foundation.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>

NS_ASSUME_NONNULL_BEGIN

@class PacketWrapper;

@interface AVPacketQueue : NSObject
{
    NSLock *_lock;
    NSMutableArray<PacketWrapper*> *_packetArray;
}

- (void)putPacket:(AVPacket*)packet;

- (AVPacket*)getPacket;

- (void)removePacket:(AVPacket*)packet;

- (void)removeAllPacket;

- (NSInteger)count;

@end

@interface PacketWrapper : NSObject
{
    AVPacket *_pPacket;
}

-(instancetype)initWithPacket:(AVPacket*)packet;

-(AVPacket*)packet;

-(void)freePacket;

@end

NS_ASSUME_NONNULL_END
