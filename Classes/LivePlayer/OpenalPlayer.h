//
//  OpenalPlayer.h
//  MyLivePlayer
//
//  Created by GevinChen on 2019/8/28.
//

#import <Foundation/Foundation.h>
#import<Openal/Openal.h>

@interface OpenalPlayer : NSObject
@property(nonatomic) int numprocessed;             //队列中已经播放过的数量
@property(nonatomic) int numqueued;                //队列中缓冲队列数量
@property(nonatomic) long long isplayBufferSize;   //已经播放了多少个音频缓存数目
@property(nonatomic) double oneFrameDuration;      //一帧音频数据持续时间(ms)
@property(nonatomic) float volume;                 //当前音量volume取值范围(0~1)
@property(nonatomic) int samplerate;               //采样率
@property(nonatomic) int bit;                      //样本值
@property(nonatomic) int channel;                  //声道数
@property(nonatomic) int datasize;                 //一帧音频数据量
@property(nonatomic) double playRate;                //播放速率


-(int)initOpenAL;

-(void)destroy;

/**
 更新 queue

 @return 播放狀態 0 已停止 1 播放中
 */
-(int)updataQueueBuffer;
-(void)playSound;
-(void)stopSound;
-(ALint)state;

-(int)enqueueBufferData:(char*)data dataSize:(int)dataSize sampleRate:(int)aSampleRate Abit:(int)aBit channel:(int)aChannel;

@end
