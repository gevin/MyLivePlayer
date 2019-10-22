//
//  AudioStreamALDecoder.m
//  MyLivePlayer
//
//  Created by GevinChen on 2019/8/29.
//

#import "AudioStreamALDecoder.h"

#define MAX_AUDIO_FRAME_SIZE 192000 // 1 second of 48khz 32bit audio
#define AUDIO_BUFFER_SECONDS  1
#define NUM_BUFFERS           3

struct PCMBuffer {
    uint8_t *pcmBuffer;
    int bufferSize;
    NSTimeInterval position;
    NSTimeInterval duration;
}PCMBuffer;

@implementation AudioStreamALDecoder
{
    AVPacketQueue           *_packetQueue;
     
    uint8_t                 *_pcmBuffer;
    NSTimeInterval           _last_position;
    NSTimeInterval           _last_timer_position;
    NSTimeInterval           _position_diff;
     
    // ffmpeg  
    CGFloat                  _audioTimeBase;
    AVFrame                 *_pAudioFrame    ;
    AVStream                *_pStream;
    AVCodecContext          *_pAudioCodecCtx;
    AVCodec                 *_pAudioCodec;
    struct SwrContext       *_au_convert_ctx;
    CGFloat                  _audioDuration;
    
    dispatch_queue_t         _filldataQueue;
    
    int                      state; // 1 running, 2 pause, 3 stop
    
    NSThread                *_thread;
    
    OpenalPlayer            *_player;
    
    int                     _pktIndex;

}


- (void)dealloc {
    NSLog(@"AudioStreamALDecoder ... dealloc");
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _filldataQueue = dispatch_queue_create("fillDataQueue", NULL);
        _packetQueue = [[AVPacketQueue alloc] init];
        _player = [[OpenalPlayer alloc] init];
        _pktIndex = 0;
    }
    return self;
}

-(int)setupWithAVStream:(AVStream *) pAVStream {
    
    _pStream = pAVStream;
    _pAudioCodecCtx = _pStream->codec;
    // 計算 audioTimeBase
    avStreamFPSTimeBase(pAVStream, 0.025, 0, &_audioTimeBase);
    
    _pAudioCodec = avcodec_find_decoder_by_name("libfdk_aac");
//    _pAudioCodec = avcodec_find_decoder(_pAudioCodecCtx->codec_id);
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
                                         AV_SAMPLE_FMT_S16,               // out_sample_fmt   (16bits per sample) int16 (-32767 ~ +32767) 
                                         _pAudioCodecCtx->sample_rate,    // out_sample_rate
                                         _pAudioCodecCtx->channel_layout, // in_channel_layout
                                         AV_SAMPLE_FMT_FLTP,              // in_sample_fmt    (32bits per sample) float (-1 ~ 1)
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
//    AudioStreamBasicDescription audioFormat = {0};
//    
//    audioFormat.mFormatID           = kAudioFormatLinearPCM;            
//    audioFormat.mFormatFlags        = kAudioFormatFlagsCanonical;
//    audioFormat.mSampleRate         = _pAudioCodecCtx->sample_rate;
//    audioFormat.mBitsPerChannel     = 8 * av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
//    audioFormat.mChannelsPerFrame   = _pAudioCodecCtx->channels;
//    audioFormat.mBytesPerFrame      = _pAudioCodecCtx->channels * av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
//    audioFormat.mBytesPerPacket     = _pAudioCodecCtx->channels * av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
//    audioFormat.mFramesPerPacket    = 1;
//    audioFormat.mReserved           = 0;
 
//    // Reference "Audio Queue Services Programming Guide"
//    int packetSize    = _pAudioCodecCtx->bit_rate/8;
//    int outBufferSize = 0;
//    int maxBufferSize = 0x50000;
//    int minBufferSize = 0x4000;
//    
//    if (audioFormat.mFramesPerPacket != 0) {
//        Float64 packetCountInTime = audioFormat.mSampleRate / audioFormat.mFramesPerPacket * AUDIO_BUFFER_SECONDS;
//        outBufferSize = packetCountInTime * packetSize;
//    } else {
//        outBufferSize = maxBufferSize > packetSize ? maxBufferSize : packetSize;
//    }
//    
//    if ( outBufferSize > maxBufferSize && outBufferSize > packetSize )
//        outBufferSize = maxBufferSize;
//    else if (outBufferSize < minBufferSize) {
//        outBufferSize = minBufferSize;
//    }
    
    [_player initOpenAL];
    
    return noErr;
}

#pragma mark - AVPacket

- (NSUInteger)packetCount {
    return _packetQueue.count; 
}

- (void)putPacket:(AVPacket*)avpacket {
    [_packetQueue putPacket:avpacket];
}

#pragma mark - PCM data

- (struct PCMBuffer)extractPCMBuffer:(AVPacket*)pPacket {
    
    struct PCMBuffer buffer;
    buffer.pcmBuffer = _pcmBuffer;
    buffer.bufferSize = 0;

    int pktSize = pPacket->size;
    if (pktSize==0) {
        [_packetQueue removePacket:pPacket];
        return buffer;
    }
    
    int got_frame_count = 0;
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
        // ffmpeg AL_FORMAT_STEREO16
        if ((buffer.bufferSize + out_buffer_size) > MAX_AUDIO_FRAME_SIZE) {
            break;
        }        
        uint8_t* data_buffer = buffer.pcmBuffer + buffer.bufferSize;
        
        int frameQuantity = swr_convert(_au_convert_ctx,
                                        &data_buffer, 
                                        _pAudioFrame->nb_samples,  // out_samples
                                        (const uint8_t **)_pAudioFrame->extended_data ,
                                        _pAudioFrame->nb_samples); // in_samples
        
        buffer.bufferSize += out_buffer_size;
        
        if (frameQuantity < 0) {
            printf("fail resample audio.\n");
            break;
        }
        got_frame_count += frameQuantity;
        
        // calculate time
        CGFloat position = av_frame_get_best_effort_timestamp(_pAudioFrame) * _audioTimeBase; // obtain pts
        CGFloat duration = av_frame_get_pkt_duration(_pAudioFrame) * _audioTimeBase;
        CGFloat timer_position = [[NSDate date] timeIntervalSince1970] - self.startTime;
        CGFloat timer_duration = timer_position - _last_timer_position;
        if (_position_diff==-999.0) {
            _position_diff = timer_position - position;
        }
        buffer.position = position;
        buffer.duration = duration;
        
        //printf("audio decode position:%0.4f, size:%d\n", position, out_buffer_size);
        // av_frame_get_best_effort_timestamp 是回傳以 time_base 為單位的 pts，所以再乘上 time_base 後就會是 pts
        printf("audio pos:%0.4f, timer:%0.4f, buffer size:%d\n", position, timer_position, out_buffer_size);
//        printf("audio position:%0.4f, timer:%0.4f \n", position, timer_position);
//        printf("audio duration:%0.4f, timer duration:%0.4f\n", duration, timer_duration);
        
        _last_position = position;
        _last_timer_position = timer_position;
        
        pktSize -= len;
    }
    _pktIndex++;
    
    return buffer;
}

#pragma mark - Run loop

- (void)mainloop {
    
    self.startTime = [[NSDate date] timeIntervalSince1970];
    _position_diff = -999.0;
    do {
        NSTimeInterval loopStart = [[NSDate date] timeIntervalSince1970];
        // 更新 player queue
        [_player updataQueueBuffer];
        
        // 有，取出 packet
        AVPacket *packet = [_packetQueue getPacket];
        
        if (packet == nil) {
            [NSThread sleepForTimeInterval:0.025];
            continue;
        }
        // 解出 pcm data
        struct PCMBuffer buffer = [self extractPCMBuffer:packet];
        
        if (buffer.bufferSize > 0) {
            // pcm data enqueue player
            [_player enqueueBufferData:buffer.pcmBuffer
                              dataSize:buffer.bufferSize
                            sampleRate:_pAudioCodecCtx->sample_rate
                                  Abit:16
                               channel:_pAudioCodecCtx->channels];
        }
        // 釋放 packet
        [_packetQueue removePacket:packet];
        
        // 檢查 player 是否停止
        if ([_player state] != AL_PLAYING) {
            // 停止的話再 play
            [_player playSound];
        }
        
        NSTimeInterval loopEnd = [[NSDate date] timeIntervalSince1970];
        NSTimeInterval workTime = loopEnd - loopStart;
        NSTimeInterval real_delay = (_player.numqueued > 35 ? 0.0232 : 0.01) - workTime;
        if (real_delay < 0) {
            real_delay = 0.01;
        }
        [NSThread sleepForTimeInterval:real_delay];
    }while (state == aldecoder_running);
    
    [_player stopSound];
}

/*
 音訊會線性增加 delay
 1. 0.01 的 delay 造成
 2. 
 
 */

#pragma mark - Decoder 

- (int)state {
    return state;
}

- (void)setVolume:(float)volume {
    _player.volume = volume;
}

- (void)start {
    if(_thread == nil) {
        state = aldecoder_running;
        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(mainloop) object:nil];
        [_thread start];
    }
}

- (void)stop {
    if (_thread) {
        state = aldecoder_stop;
        [_thread cancel];
        [_player stopSound];
        _thread = nil;
    }    
}

- (void)destroy {
    [_player destroy];
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
    
    NSTimeInterval time = [[NSDate date] timeIntervalSince1970] - self.startTime - _position_diff;
    return time;
}


@end
