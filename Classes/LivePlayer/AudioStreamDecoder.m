//
//  AudioStreamDecoder.m
//  MyLivePlayer
//
//  Created by GevinChen on 19/8/22.
//  Copyright (c) 2019年 GevinChen. All rights reserved.

#import "AudioStreamDecoder.h"
#import "AVPacketQueue.h"
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#import "Utilities.h"

#define MAX_AUDIO_FRAME_SIZE 192000 // 1 second of 48khz 32bit audio
#define AUDIO_BUFFER_SECONDS  1
#define NUM_BUFFERS           3

@implementation AudioStreamDecoder
{
    NSLock                 *_lock;
    
    // audio queue
    AudioQueueRef           _audioQueue;
    AudioQueueBufferRef     _bufferArray[NUM_BUFFERS];
    // #Gevin_note: 採用填 silence data 的方式後，就不需要標 tag 了，因為每個 loop 都不會停止。
    //BOOL                    _inUseFlag[NUM_BUFFERS]; 
    NSTimer                *_timerArray[NUM_BUFFERS];
    AVPacketQueue          *_packetQueue;
    
    uint8_t                *_pcmBuffer;
    NSTimeInterval          _last_position;
    NSTimeInterval          _last_timer_position;
    NSTimeInterval          _position_diff;
    
    // ffmpeg 
    CGFloat                 _audioTimeBase;
    AVFrame                *_pAudioFrame    ;
    AVStream               *_pStream;
    AVCodecContext         *_pAudioCodecCtx;
    AVCodec                *_pAudioCodec;
    struct SwrContext      *_au_convert_ctx;
    CGFloat                 _audioDuration;
    
    dispatch_queue_t        _filldataQueue;
    
    int                     state; // 1 running, 2 pause, 3 stop
}

- (void)dealloc {
    NSLog(@"AudioStreamDecoder ... dealloc");
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _filldataQueue = dispatch_queue_create("fillDataQueue", NULL);
        _packetQueue = [[AVPacketQueue alloc] init];

    }
    return self;
}

-(int)setupWithAVStream:(AVStream *) pAVStream {
    
    _pStream = pAVStream;
    _pAudioCodecCtx = _pStream->codec;
    // 計算 audioTimeBase
    avStreamFPSTimeBase(pAVStream, 0.025, 0, &_audioTimeBase);
    
    // _pAudioCodec = avcodec_find_decoder_by_name("libfdk_aac");
    _pAudioCodec = avcodec_find_decoder(_pAudioCodecCtx->codec_id);
    if(_pAudioCodec == NULL) {
        printf("Unsupported audio codec!\n");
        return -1;
    }
    if(avcodec_open2(_pAudioCodecCtx, _pAudioCodec, NULL) < 0) {
        printf("Cannot open audio decoder\n");
        return -1;
    }
    
    NSLog(@"== Audio pCodec Information");
    NSLog(@"name = %s",_pAudioCodec->name);
    if(*(_pAudioCodec->sample_fmts)) {
        NSLog(@"sample_fmts = %d",*(_pAudioCodec->sample_fmts));
    }
    if(_pAudioCodec->profiles)
        NSLog(@"profiles = %s",_pAudioCodec->name);
    else
        NSLog(@"profiles = NULL");
    
    if(_pAudioCodecCtx->bit_rate==0) {
        _pAudioCodecCtx->bit_rate = 0x100000;//0x50000;
    }
    // frame count per packet
    if(_pAudioCodecCtx->frame_size==0) {
        _pAudioCodecCtx->frame_size=1024;
        //NSLog(@"pAudioCodecCtx->frame_size=0");
    }
    
    //Swr 重採樣
    _au_convert_ctx = swr_alloc();
    _au_convert_ctx = swr_alloc_set_opts(_au_convert_ctx, 
                                         _pAudioCodecCtx->channel_layout, // out_channel_layout AV_CH_LAYOUT_STEREO, AV_CH_LAYOUT_MONO
                                         AV_SAMPLE_FMT_S16,               // out_sample_fmt
                                         _pAudioCodecCtx->sample_rate,    // out_sample_rate
                                         _pAudioCodecCtx->channel_layout, // in_channel_layout
                                         AV_SAMPLE_FMT_FLTP,              // in_sample_fmt
                                         _pAudioCodecCtx->sample_rate,    // in_sample_rate
                                         0,
                                         NULL);
    swr_init(_au_convert_ctx);
    
    _pcmBuffer = malloc(MAX_AUDIO_FRAME_SIZE);
    _pAudioFrame = av_frame_alloc();
    
    
    // support audio play when screen is locked
    NSError *setCategoryErr = nil;
    NSError *activationErr  = nil;
    
    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayback error:&setCategoryErr];
    [[AVAudioSession sharedInstance] setActive:YES error:&activationErr];
    
    // 1 Config Audio Format
    AudioStreamBasicDescription audioFormat = {0};
    
    audioFormat.mFormatID           = kAudioFormatLinearPCM;            
    audioFormat.mFormatFlags        = kAudioFormatFlagsCanonical;
    audioFormat.mSampleRate         = _pAudioCodecCtx->sample_rate;
    audioFormat.mBitsPerChannel     = 8 * av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
    audioFormat.mChannelsPerFrame   = _pAudioCodecCtx->channels;
    audioFormat.mBytesPerFrame      = _pAudioCodecCtx->channels * av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
    audioFormat.mBytesPerPacket     = _pAudioCodecCtx->channels * av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
    audioFormat.mFramesPerPacket    = 1;
    audioFormat.mReserved           = 0;

    // The default audio data defined by APPLE is 16bits.
    // If we got 32 or 8, we should covert it to 16bits

    // 2 create AudioQueue
    // # 1. 建立一個 Audio Queue (audioQueue)，並設定對應的 call back 函數為 HandleOutputBuffer()
    OSStatus err = AudioQueueNewOutput(&audioFormat,        // 音訊格式
                                       AudioOutputCallback,  // buffer 被使用完成後的 callback
                                       (__bridge void *)(self),
                                       NULL,                // callback 需要在的哪個RunLoop上被回調，若傳 NULL 就會在 AudioQueue 的内部 RunLoop 中被回調，也可以自己生成一個 dispatch_queue_t 然後傳入
                                       NULL,                // RunLoop模式，NULL 就相當於 kCFRunLoopCommonModes，一般傳 NULL 即可
                                       0,                   // 目前沒作用，傳 0 
                                       &_audioQueue);       // 回傳生成的 AudioQueue 實例
    if (err !=noErr ) {
        NSLog(@"*** AudioQueue Error : Creating audio output queue: %d", err);
        return err;
    }

    // 3 create AudioQueueBuffer
    
    // Reference "Audio Queue Services Programming Guide"
    int packetSize    = _pAudioCodecCtx->bit_rate/8;
    int outBufferSize = 0;
    int maxBufferSize = 0x50000;
    int minBufferSize = 0x4000;
    
    if (audioFormat.mFramesPerPacket != 0) {
        Float64 packetCountInTime = audioFormat.mSampleRate / audioFormat.mFramesPerPacket * AUDIO_BUFFER_SECONDS;
        outBufferSize = packetCountInTime * packetSize;
    } else {
        outBufferSize = maxBufferSize > packetSize ? maxBufferSize : packetSize;
    }
    
    if ( outBufferSize > maxBufferSize && outBufferSize > packetSize )
        outBufferSize = maxBufferSize;
    else if (outBufferSize < minBufferSize) {
        outBufferSize = minBufferSize;
    }
    
    for (int i=0; i<NUM_BUFFERS; i++) {
        err = AudioQueueAllocateBufferWithPacketDescriptions(_audioQueue, 
                                                             outBufferSize, // inBufferByteSize
                                                             1, // inNumberPacketDescriptions
                                                             &_bufferArray[i]);
        if (err != noErr) {
            NSLog(@"*** AudioQueue Error : Could not allocate audio queue buffer: %d", err);
            AudioQueueDispose(_audioQueue, YES);
            return err;
        }
    }

    // 設置音量
    Float32 gain=1.0; 
    AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Volume, gain);

    // listener AudioQueue property change
    AudioQueueAddPropertyListener(_audioQueue,
                                  kAudioQueueProperty_IsRunning,
                                  CheckAudioQueueRunningStatus,
                                  (__bridge void *)(self));
    
    return noErr;
}

#pragma mark - fill data into buffer

- (void)refillBuffer:(AudioQueueBufferRef)buffer after:(CGFloat)delay{
    int index = [self getAudioBufferIndex:buffer];
    printf("refill Buffer %d, delay:%.04f\n",index,delay);
    if (delay>0) {
        dispatch_after(DISPATCH_TIME_NOW + delay, dispatch_get_main_queue(), ^{
            [self fillDataIntoBuffer:buffer];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self fillDataIntoBuffer:buffer];
        });
    }
}

- (void)fillDataIntoBuffer:(AudioQueueBufferRef)audioBuffer {
    
    if (audioBuffer == nil) {
        printf("Audio Queue: There is no buffer available.\n");
//        [self debug];
        return;
    }
    if(state == handler_stop) {
        return;
    }
    
    audioBuffer->mAudioDataByteSize = 0;
    audioBuffer->mPacketDescriptionCount = 0;
    int index = [self getAudioBufferIndex:audioBuffer];

    // # get audio packet from queue
    AVPacket *pPacket = [_packetQueue getPacket];   
    
    if (pPacket == nil) {
        [self fillSilenceData:audioBuffer index:index];
        return;
    }
    
    int pktSize = pPacket->size;
    if (pktSize==0) {
        [_packetQueue removePacket:pPacket];
        [self fillSilenceData:audioBuffer index:index];
        return;
    }
    
    int got_frame_count = 0;
    // 1 packet has multi frame
    while (pktSize > 0) {
        int got_frame = 0;
        int len = 0;
        len = avcodec_decode_audio4( _pAudioCodecCtx, _pAudioFrame, &got_frame, pPacket);
        if ( len < 0 ) {
            printf("Error in decoding audio frame.\n");
            //return -1;
            break;
        }
        
        if (got_frame == 0) {
            pktSize -= len;
            continue;
        }
        
        int out_buffer_size = av_samples_get_buffer_size(_pAudioFrame->linesize, 
                                                         _pAudioCodecCtx->channels,
                                                         _pAudioFrame->nb_samples,
                                                         AV_SAMPLE_FMT_S16,
                                                         0);
        int frameQuantity = swr_convert(_au_convert_ctx,
                                        &_pcmBuffer, 
                                        _pAudioFrame->nb_samples,  // out_samples
                                        (const uint8_t **)_pAudioFrame->extended_data ,
                                        _pAudioFrame->nb_samples); // in_samples
        //printf("frame quantity %d\n", frameQuantity);
        if (frameQuantity < 0) {
            printf("fail resample audio.\n");
            break;
        }
        got_frame_count += frameQuantity;
        
        // calculate time
        //
        CGFloat position = av_frame_get_best_effort_timestamp(_pAudioFrame) * _audioTimeBase; // obtain pts
        CGFloat duration = av_frame_get_pkt_duration(_pAudioFrame) * _audioTimeBase;
        CGFloat timer_position = [[NSDate date] timeIntervalSince1970] - self.startTime;
        CGFloat timer_duration = timer_position - _last_timer_position;
        _position_diff = timer_position - position;
//        printf("audio %d decode position:%0.4f, size:%d\n", index, position, out_buffer_size);
        // av_frame_get_best_effort_timestamp 是回傳以 time_base 為單位的 pts，所以再乘上 time_base 後就會是 pts
        printf("audio %d pos:%0.4f, timer:%0.4f, diff:%.04f, pkt size:%d, buffer size:%d\n", index, position, timer_position, _position_diff, pktSize, out_buffer_size);
        //printf("audio position:%0.4f\n", position);
        //printf("audio duration:%0.4f, timer duration:%0.4f\n", duration, timer_duration);
        
        _last_position = position;
        _last_timer_position = timer_position;
        
        // put pcm data into AudioBuffer
        if (audioBuffer->mAudioDataBytesCapacity - audioBuffer->mAudioDataByteSize >= out_buffer_size) {
            memcpy((uint8_t *)audioBuffer->mAudioData + audioBuffer->mAudioDataByteSize, _pcmBuffer, out_buffer_size);
            audioBuffer->mPacketDescriptions[audioBuffer->mPacketDescriptionCount].mStartOffset = audioBuffer->mAudioDataByteSize;
            audioBuffer->mPacketDescriptions[audioBuffer->mPacketDescriptionCount].mDataByteSize = out_buffer_size;
            audioBuffer->mPacketDescriptions[audioBuffer->mPacketDescriptionCount].mVariableFramesInPacket = 1;
            audioBuffer->mAudioDataByteSize += out_buffer_size;
            audioBuffer->mPacketDescriptionCount++;
        } else {
            printf("** AudioBuffer capacity do not sufficient to fill pcm data.\n");
            printf("** AudioDataBytesCapacity:%d, AudioDataByteSize:%d, pcm data size:%d .\n",audioBuffer->mAudioDataBytesCapacity , audioBuffer->mAudioDataByteSize, out_buffer_size );
        }
        
        pktSize -= len;
    }
    
    [_packetQueue removePacket:pPacket];
    
    if (got_frame_count == 0) {
        [self fillSilenceData:audioBuffer index:index];
        return;
    }
    
    // enqueue    
    OSStatus err = AudioQueueEnqueueBuffer(_audioQueue,
                                           audioBuffer,
                                           0,
                                           NULL);
    if (err != noErr) {
        NSLog(@"** AudioQueue : Error enqueuing audio buffer: %d", err);
    }
}

- (void)fillSilenceData:(AudioQueueBufferRef)buffer index:(int)index {
    
    int silenceDataSize = buffer->mAudioDataByteSize;
    if(silenceDataSize==0) {
        silenceDataSize = 1024*2;
    }
    //printf("audio %d fill silence data size:%d\n", index, silenceDataSize);
    // 20130427 set silence data to real silence
    memset(buffer->mAudioData,0,silenceDataSize);
    buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mStartOffset = buffer->mAudioDataByteSize;
    buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mDataByteSize = silenceDataSize;
    buffer->mPacketDescriptions[buffer->mPacketDescriptionCount].mVariableFramesInPacket = 1;
    buffer->mAudioDataByteSize += silenceDataSize;
    buffer->mPacketDescriptionCount++;
    
    OSStatus err = AudioQueueEnqueueBuffer(_audioQueue,
                                           buffer,
                                           0,
                                           NULL);
    if (err != noErr) {
        NSLog(@"** AudioQueue : Error enqueuing audio buffer: %d", err);
    }
}

#pragma mark - AVPacket

- (NSUInteger)packetCount {
    return _packetQueue.count; 
}

- (void)putPacket:(AVPacket*)avpacket {
    [_packetQueue putPacket:avpacket];
}

#pragma mark - AudioBuffer

- (int)getAudioBufferIndex:(AudioQueueBufferRef)buffer {
    for(int i=0; i<NUM_BUFFERS; i++) {
        if(buffer == _bufferArray[i]) {
            return i;
        }
    }
    return -1;
}

- (void)setVolume:(float)volume {
    AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Volume, volume);
}

- (BOOL)isQueueRunning {
    UInt32 flag = 0;
    OSStatus ret = 0;
    UInt32 size=sizeof(UInt32);
    ret = AudioQueueGetProperty(_audioQueue,
                                kAudioQueueProperty_IsRunning,
                                &flag,
                                &size);
    return flag==1;
}

- (int)state {
    return state;
}

- (void)start {
    state = handler_running;
    self.startTime = [[NSDate date] timeIntervalSince1970];
    
    for(int i=0; i<NUM_BUFFERS; i++) {
        [self fillDataIntoBuffer:_bufferArray[i]];
    }
    
    OSStatus err=AudioQueueStart(_audioQueue, nil);
    if (err != noErr) {
        NSLog(@"AudioQueueStart() error %d", err);
    }
}

- (void)stop {
    state = handler_stop;
    for (int i=0; i<NUM_BUFFERS; i++) {
        if(_timerArray[i]) {
            [_timerArray[i] invalidate];
            _timerArray[i] = nil;
        }
    }
    AudioQueueStop(_audioQueue, NO);
}

- (void)destroy {
    OSStatus err = AudioQueueDispose(_audioQueue, NO);
    if (err != noErr) {
        NSLog(@"AudioQueueDispose error %d", err);
    }
    
    [_packetQueue removeAllPacket];
    
    if(_au_convert_ctx) {
        swr_free(&_au_convert_ctx);
        _au_convert_ctx = nil;
    }
    
    free(_pcmBuffer);
    av_frame_free(&_pAudioFrame);
    _pAudioFrame = nil;

}

- (NSTimeInterval)getAudioStreamingTime {
    NSTimeInterval real_timer_position = [[NSDate date] timeIntervalSince1970] - self.startTime;
    return real_timer_position - _position_diff;
}

// buffer 使用完畢的 callback
static void AudioOutputCallback (void                 *aqData,
                          AudioQueueRef        inAQ,
                          AudioQueueBufferRef  inBuffer) {
    AudioStreamDecoder* handler = (__bridge AudioStreamDecoder*)aqData;
    [handler fillDataIntoBuffer:inBuffer];
}

// 監聽 audio queue 屬性狀態變化
void CheckAudioQueueRunningStatus(void *inUserData,
                                  AudioQueueRef           inAQ,
                                  AudioQueuePropertyID    inID) {
    
    if(inID == kAudioQueueProperty_IsRunning) {
        
        AudioStreamDecoder *decoder = (__bridge AudioStreamDecoder*)inUserData;
        UInt32 flag = 0;
        OSStatus ret = 0;
        UInt32 size=sizeof(UInt32);
        ret = AudioQueueGetProperty(inAQ,
                                    kAudioQueueProperty_IsRunning,
                                    &flag,
                                    &size);
        printf("AudioQueue: property change ... IsRunning : %d\n", flag);
//        if(flag==0) {
//            [decoder restart];
//        }
    }
}

@end
