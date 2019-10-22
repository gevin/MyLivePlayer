//
//  AudioStreamALDecoder.h
//  MyLivePlayer
//
//  Created by GevinChen on 2019/8/29.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "OpenalPlayer.h"
#import "Utilities.h"
#import "AVPacketQueue.h"
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>

NS_ASSUME_NONNULL_BEGIN

enum ALDecoderStatus {
    aldecoder_running = 1,
    aldecoder_pause = 2,
    aldecoder_stop = 3
}ALDecoderStatus;

@interface AudioStreamALDecoder : NSObject

@property (nonatomic) NSTimeInterval startTime;

- (int)setupWithAVStream:(AVStream *) pAVStream;

- (NSUInteger)packetCount;

- (void)putPacket:(AVPacket*)avpacket;

- (void)setVolume:(float)volume;

- (int)state;

- (void)start;

- (void)stop;

- (void)destroy;

- (NSTimeInterval)getAudioStreamingTime;

@end

NS_ASSUME_NONNULL_END
