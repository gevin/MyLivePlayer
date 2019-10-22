//
//  StreamingHandler.m
//  MyLivePlayer
//
//  Created by GevinChen on 19/7/12.
//  Copyright (c) 2019年 GevinChen. All rights reserved.


#import "StreamingHandler.h"
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>

static BOOL avcodecInit = NO;

@implementation StreamingHandler
{
    AVFormatContext     *_pFormatCtx;
    AVCodecContext      *_pVideoCodecCtx;
    AVCodecContext      *_pAudioCodecCtx;
    int                 _videoStreamIndex;
    int                 _audioStreamIndex;
    
    NSThread*           _thread;
    BOOL                _running;
}

-(void)dealloc {
    NSLog(@"StreamingHandler ... dealloc");
}

-(id)init
{
    if (!(self=[super init])) return nil;
    _audioDecoder = [[AudioStreamALDecoder alloc] init];
    _videoDecoder = [[VideoStreamDecoder alloc] init];

    return self;
}

- (GLESView*)glView {
    return _videoDecoder.glView;
}

- (void)mainLoop
{
    if (_running) {
        return;
    }
    _running = YES;
    
    if ( !avcodecInit ) {
        // Register all formats and codecs
        avcodec_register_all();
        av_register_all();
        avformat_network_init();
    }
    
    // Open video file
    if(avformat_open_input(&_pFormatCtx, [self.videoPath UTF8String], NULL, NULL) != 0) {
        printf("Couldn't open %s\n",[self.videoPath UTF8String]);
        _thread = nil;
        return;
    }
    
    // Retrieve stream information
    if(avformat_find_stream_info(_pFormatCtx,NULL) < 0) {
        printf("Couldn't find stream information\n");
        _thread = nil;
        return;
    }
    
    // Dumpt stream information
    av_dump_format(_pFormatCtx, 0, [self.videoPath UTF8String], 0);
    
    // Find audio, video stream
    _videoStreamIndex = -1;
    _audioStreamIndex = -1;
    for(int i=0; i<_pFormatCtx->nb_streams; i++) {
        if(_videoStreamIndex == -1 && _pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_VIDEO){
            _videoStreamIndex = i;
        }
        if(_audioStreamIndex == -1 && _pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_AUDIO){
            _audioStreamIndex = i;
        }
    }
    if (_videoStreamIndex < 0 && _audioStreamIndex < 0) {
        printf("Cannot find a any stream in the input file\n");
        _thread = nil;
        return;
    }
    
    // init decoder
    int ret = [_audioDecoder setupWithAVStream: _pFormatCtx->streams[_audioStreamIndex] ];
    if (ret<0) {
        _thread = nil;
        return;
    }
    [_audioDecoder setVolume:1.0];
    
    ret = [_videoDecoder setupWithAVStream: _pFormatCtx->streams[_videoStreamIndex]];
    if (ret<0) {
        _thread = nil;
        return;
    }
    _videoDecoder.audioDecoder = _audioDecoder;
    
    //  call back
    if (self.delegate && [self.delegate respondsToSelector:@selector(videoStart)] ) {
        [self.delegate performSelectorOnMainThread:@selector(videoStart) withObject:nil waitUntilDone:YES];
    }
    
    //[_videoDecoder start];
    //[_audioDecoder start];
    BOOL decoderStart = NO;
    BOOL noMoreFrames = NO;
    NSTimeInterval delay = 0.01;
    do {
        AVPacket *pPacket = nil;
        if(!noMoreFrames) {
            pPacket = (AVPacket *)av_packet_alloc();
            int ret = av_read_frame(_pFormatCtx, pPacket);
            if( ret < 0 ){
                printf("occur error when read a frame, %d %s!!\n", ret, av_err2str(ret));
                // 不能馬上結束，要等 video audio decoder 的 packet queue 都解析完才行
                noMoreFrames = YES;
                delay = 1.0/5.0;
                av_packet_free(&pPacket);
                continue;
            }
        }
        
        // if got packet
        if (pPacket) {
            if (pPacket->stream_index == _videoStreamIndex) {
                [_videoDecoder putPacket:pPacket];
            } else if (pPacket->stream_index == _audioStreamIndex) {
                [_audioDecoder putPacket:pPacket];
            }else{
                av_packet_free(&pPacket);
                continue;
            }
        }
        
        // 延遲開始，由於 AudioQueue 的特性，只要 input buffer 中斷，它就會停止播放
        // 最好是不要讓 packet 中斷，所以等 audio packet 累積一點量後再開始
        if (decoderStart == NO && [_audioDecoder packetCount] > 128 ) {
            decoderStart = YES;
            [_videoDecoder start];
            [_audioDecoder start];
        }
        
        // 沒有 frame 可讀，且剩下的 packet 都解析完了
        if(noMoreFrames && [_videoDecoder packetCount] == 0 && [_audioDecoder packetCount] == 0 ) {
            _running = NO;
        }
        
        [NSThread sleepForTimeInterval:delay];
    }while (_running);
    
    printf("decode thread exit!\n");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        _thread = nil;
        [_videoDecoder stop];
        [_videoDecoder destroy];
        [_audioDecoder stop];
        [_audioDecoder destroy];
        _videoDecoder = nil;
        _audioDecoder = nil;
        [self destroy];
    });
    
    //  call back
    if (self.delegate && [self.delegate respondsToSelector:@selector(videoEnd)] ) {
        [self.delegate performSelectorOnMainThread:@selector(videoEnd) withObject:nil waitUntilDone:YES];
    }
}

- (CGSize)sourceSize
{
    return (CGSize){_pVideoCodecCtx->width, _pVideoCodecCtx->height};
}

- (BOOL)isPlaying
{
    return (_thread);
}

- (void)start
{
    if ( _thread == nil && self.videoPath.length > 0 ) {
        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(mainLoop) object:nil];
        [_thread start];
    }
}

- (void)stop
{
    _running = NO;
    [_thread cancel];
    dispatch_async(dispatch_get_main_queue(), ^{
        _thread = nil;
        [_videoDecoder stop];
        [_videoDecoder destroy];
        [_audioDecoder stop];
        [_audioDecoder destroy];
        _videoDecoder = nil;
        _audioDecoder = nil;
        [self destroy];
    });

}

-(void)destroy
{
    // Close the codec
    if (_pVideoCodecCtx) {
        avcodec_close(_pVideoCodecCtx);
        _pVideoCodecCtx = nil;
    } 
    if(_pAudioCodecCtx) {
        avcodec_close(_pAudioCodecCtx);
        _pAudioCodecCtx = nil;
    }
    
    // Close the video file
    if (_pFormatCtx) {
        avformat_close_input(&_pFormatCtx);
        _pFormatCtx = nil;
    }
}

//  線性內插計算 A from, B to, C dt, dt 為 0~1，代表 A ~ B 的值
//  dt = 0, 回傳 A， dt = 1 回傳 B， dt = 0.5，回傳 A~B 的中間值
#define LERP(A,B,C) ((A)*(1.0-C)+(B)*C)




@end
