//
//  VideoStreamDecoder.m
//  MyLivePlayer
//
//  Created by GevinChen on 19/8/24.
//  Copyright (c) 2019年 GevinChen. All rights reserved.

#import "VideoStreamDecoder.h"
#import "AVPacketQueue.h"

#import "Utilities.h"

@implementation VideoStreamDecoder
{
    NSThread               *_thread;
    //NSLock                 *_lock;
    //dispatch_queue_t        _workingQueue;
    
    AVPacketQueue          *_packetQueue;
    
    NSTimeInterval          _last_position;
    NSTimeInterval          _last_timer_position;
    
    CGFloat                 _fps;
    CGFloat                 _videoTimeBase; 
    AVFrame                *_pVideoFrame;
    AVCodecContext         *_pVideoCodecCtx;
    AVCodec                *_pVideoCodec;
    AVStream               *_pStream;
    char                   *_yuvBuffer;
    
    BOOL                    _running;
}

- (void)dealloc {
    NSLog(@"VideoStreamDecoder ... dealloc");
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        //_lock = [[NSLock alloc] init];
        //_workingQueue = dispatch_queue_create("Video Decode Queue", DISPATCH_QUEUE_SERIAL);
        _packetQueue = [[AVPacketQueue alloc] init];
        _glView = [[GLESView alloc] initWithFrame:(CGRect){0,0,320,320}];
    }
    return self;
}

-(int)setupWithAVStream:(AVStream *) pAVStream {
    
    _pStream = pAVStream;
    
    // Get a pointer to the codec context for the video stream
    _pVideoCodecCtx = _pStream->codec;
    
    // 計算 videoTimeBase
    avStreamFPSTimeBase(_pStream, 0.04, &_fps, &_videoTimeBase);
    
    // Find the decoder for the video stream
    _pVideoCodec = avcodec_find_decoder(_pVideoCodecCtx->codec_id);
    if(_pVideoCodec == NULL) {
        printf("Unsupported video codec!\n");
        return -1;
    }
    // Open codec
    if(avcodec_open2(_pVideoCodecCtx, _pVideoCodec, NULL) < 0) {
        printf("Cannot open video decoder\n");
        return -1;
    }
    
    _pVideoFrame = av_frame_alloc();
    
    int width = _pVideoCodecCtx->width;
    int height = _pVideoCodecCtx->height;
    _yuvBuffer = (char *)malloc(width * height * 3 / 2);
    
    [self setupGLView];
    return 0;
}

#pragma mark - AVPacket

- (NSUInteger)packetCount {
    return _packetQueue.count; 
}

- (void)putPacket:(AVPacket*)avpacket {
    [_packetQueue putPacket:avpacket];
}

#pragma mark - Run loop

- (void)mainLoop {
    
    int got_frame;
    
    NSTimeInterval loopStart;
    NSTimeInterval loopEnd;
    NSTimeInterval delay = 1.0/_fps;
    
    _running = YES;
    do{
        
        loopStart = [[NSDate date] timeIntervalSince1970];
        
        AVPacket *pPacket = [_packetQueue getPacket];
        
        if(pPacket == nil) {
            [NSThread sleepForTimeInterval:0.02];
            continue;
        }
        
        // Decode video frame
        int ret = avcodec_decode_video2(_pVideoCodecCtx, _pVideoFrame, &got_frame, pPacket);
        if ( ret < 0 ) {
            printf("occur error when decode a frame, %d %s!!\n", ret, av_err2str(ret) );
        }
        
        // no frame
        if (got_frame == 0) {
            continue;
        }
        // error
        else if(got_frame<0){
            printf("occur error when decode a frame, %d!!\n", got_frame);
            break;
        }
        
        int w, h;
        char *y, *u, *v;
        w = _pVideoFrame->width;
        h = _pVideoFrame->height;
        y = _yuvBuffer;
        u = y + w * h;
        v = u + w * h / 4;
        
        /*
         有些影像解碼出來，右邊會有一點 padding 所以有時候 pFrame->linesize[0] 並不直接等於 pFrame->width
         會是 pFrame->linesize[0] = pFrame->width + padding
         所以才會採取一行一行複製，來濾除 padding
         */
        for (int i=0; i<h; i++)
            memcpy(y + w * i, _pVideoFrame->data[0] + _pVideoFrame->linesize[0] * i, w);
        for (int i=0; i<h/2; i++)
            memcpy(u + w / 2 * i, _pVideoFrame->data[1] + _pVideoFrame->linesize[1] * i, w / 2);
        for (int i=0; i<h/2; i++)
             memcpy(v + w / 2 * i, _pVideoFrame->data[2] + _pVideoFrame->linesize[2] * i, w / 2);
             
        dispatch_async( dispatch_get_main_queue(), ^{
            [self.glView displayYUV420pData:_yuvBuffer];
            [self.glView render:nil];
        });
        
        double position = av_frame_get_best_effort_timestamp(_pVideoFrame) * _videoTimeBase;
        double duration = av_frame_get_pkt_duration(_pVideoFrame) * _videoTimeBase;
        duration += _pVideoFrame->repeat_pict * _videoTimeBase * 0.5;
        
        CGFloat timer_position = [[NSDate date] timeIntervalSince1970] - self.startTime;
        CGFloat timer_duration = timer_position - _last_timer_position;
        NSTimeInterval audio_position = [self.audioDecoder getAudioStreamingTime];
        NSTimeInterval audio_video_diff = audio_position - position;
//        printf("video position:%0.4f, tmier:%0.4f, diff:%.04f, audio position:%.04f, audio_video_diff:%.04f\n", position, timer_position, timer_position - position, audio_position, audio_position - position );
        printf("audio position:%.04f, video position:%0.4f, audio_video_diff:%.04f\n", audio_position, position, audio_video_diff );
        //printf("video duration:%0.4f, timer duration:%0.4f\n", duration, timer_duration);
        
        _last_position = position;
        _last_timer_position = timer_position;
        
        loopEnd = [[NSDate date] timeIntervalSince1970];
        
        NSTimeInterval loop_duration = loopEnd - loopStart;
        delay = duration - loop_duration;
        delay -= audio_video_diff;
        if (delay <= 0 ) {
            delay = 0.016;
        }
//        printf("video loop delay: %.03f\n", delay);
        [_packetQueue removePacket:pPacket];
        [NSThread sleepForTimeInterval:delay];

    }while(_running);
    
    [_packetQueue removeAllPacket];
}


- (int)isRunning {
    return _running;
}

- (void)start {
    
    if ( _thread == nil ) {
        self.startTime = [[NSDate date] timeIntervalSince1970];
        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(mainLoop) object:nil];
        [_thread start];
    }
}

- (void)stop {
    
    @synchronized (self) {
        _running = NO;
        [_thread cancel];
        _thread = nil;
    }
}


- (void)destroy {
    av_free(_pVideoFrame);
    
    free(_yuvBuffer);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [_glView removeFromSuperview];
    });
    
}

- (void)setupGLView {
    
    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat scale = UIScreen.mainScreen.bounds.size.width / (CGFloat)_pVideoCodecCtx->width; 
        CGFloat width = _pVideoCodecCtx->width * scale;
        CGFloat height = _pVideoCodecCtx->height * scale;
        CGSize displaySize = CGSizeMake(width, height);
        
        _glView.frame = (CGRect){0,0,displaySize};
        [_glView setupGLWithBufferSize:CGSizeMake(_pVideoCodecCtx->width, _pVideoCodecCtx->height)];
    });
    
}

@end
