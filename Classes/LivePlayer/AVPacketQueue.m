//
//  AudioStreamingDataQueue.m
//  MyLivePlayer
//
//  Created by GevinChen on 19/8/22.
//  Copyright (c) 2019年 GevinChen. All rights reserved.

#import "AVPacketQueue.h"

@implementation AVPacketQueue

- (instancetype)init
{
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
        _packetArray = [[NSMutableArray alloc] init]; 
    }
    return self;
}

- (void)putPacket:(AVPacket*)packet {
    [_lock lock];
    PacketWrapper *wrapper = [[PacketWrapper alloc] initWithPacket:packet];
    [_packetArray addObject:wrapper];
    [_lock unlock];
}

- (AVPacket*)getPacket {
    [_lock lock];
    if (_packetArray.count == 0 ) {
        [_lock unlock];
        return nil;
    }
    PacketWrapper* wrapper = [_packetArray objectAtIndex:0];
    [_lock unlock];
    return [wrapper packet];
}

- (void)removePacket:(AVPacket*)packet {
    [_lock lock];
    for(int i=0; i<_packetArray.count ; i++) {
        PacketWrapper *wrapper = _packetArray[i];
        if ([wrapper packet] == packet) {
            [_packetArray removeObject:wrapper];
            [wrapper freePacket];
            break;
        }
    }
    [_lock unlock];    
}

- (void)removeAllPacket {
    [_lock lock];
    for(int i=0; i<_packetArray.count ; i++) {
        PacketWrapper *wrapper = _packetArray[i];
        [wrapper freePacket];
    }
    [_packetArray removeAllObjects];
    [_lock unlock];        
}

- (NSInteger)count {
    return _packetArray.count;
}

@end


@implementation PacketWrapper

-(instancetype)initWithPacket:(AVPacket*)packet {
    self=[super init];
    if (self) {
        _pPacket = packet;
    }
    return self;
}

-(AVPacket*)packet {
    return _pPacket;
}

-(void)freePacket {
    av_free(_pPacket);
}

@end
