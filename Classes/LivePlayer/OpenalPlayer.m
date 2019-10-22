//
//  OpenalPlayer.m
//  MyLivePlayer
//
//  Created by GevinChen on 2019/8/28.
//

#import "OpenalPlayer.h"

@implementation OpenalPlayer{
    
    ALCdevice  * _Devicde;          //device句柄
    ALCcontext * _Context;         //device context
    ALuint       _sourceId;           //source id 负责播放
    NSLock     * lock;
    float        rate;
    // key bufferId / value buffer address
    NSMutableDictionary *_bufferDict;
    float       _volume;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _bufferDict = [[NSMutableDictionary alloc] init];
    }
    return self;
}

-(int)initOpenAL{
    
    int ret = 0;
    lock = [[NSLock alloc]init];
    printf("=======initOpenAl===\n");
    rate = 1.0;
    _Devicde = alcOpenDevice(NULL);
    if (_Devicde)
    {
        //建立声音文本描述
        _Context = alcCreateContext(_Devicde, NULL);
        //设置行为文本描述
        alcMakeContextCurrent(_Context);
    }else
        ret = -1;
    
    //创建一个source并设置一些属性
    alGenSources(1, &_sourceId);
    alSpeedOfSound(1.0);
    alDopplerVelocity(1.0);
    alDopplerFactor(1.0);
    alSourcef(_sourceId, AL_PITCH, 1.0f);
    alSourcef(_sourceId, AL_GAIN, 1.0f);
    alSourcei(_sourceId, AL_LOOPING, AL_FALSE);
    alSourcef(_sourceId, AL_SOURCE_TYPE, AL_STREAMING);
    
    return ret;
}

-(void)destroy{
    
    printf("=======cleanUpOpenAL===\n");
    alDeleteSources(1, &_sourceId);
    
    ALCcontext * Context = alcGetCurrentContext();
    // ALCdevice * Devicde = alcGetContextsDevice(Context);
    
    if (Context)
    {
        alcMakeContextCurrent(NULL);
        alcDestroyContext(Context);
        _Context = NULL;
    }
    alcCloseDevice(_Devicde);
    _Devicde = NULL;
}

-(ALint)state {
    ALint stateValue = 0;
    alGetSourcei(_sourceId, AL_SOURCE_STATE, &stateValue);
    return stateValue;
}

-(int)enqueueBufferData:(char*)data dataSize:(int)dataSize sampleRate:(int) aSampleRate Abit:(int)aBit channel:(int)aChannel {
    
    int ret = 0; 
    //样本数openal的表示方法
    ALenum format = 0;
    //buffer id 负责缓存,要用局部变量每次数据都是新的地址
    ALuint bufferID = 0;
    
    if (_datasize == 0 &&
        _samplerate == 0 &&
        _bit == 0 &&
        _channel == 0)
    {
        if (dataSize != 0 &&
            aSampleRate != 0 &&
            aBit != 0 &&
            aChannel != 0)
        {
            _datasize = dataSize;
            _samplerate = aSampleRate;
            _bit = aBit;
            _channel = aChannel;
            _oneFrameDuration = _datasize * 1.0 /(_bit/8) /_channel /_samplerate * 1000 ;   //计算一帧数据持续时间
        }
    }
    
    //创建一个buffer
    alGenBuffers(1, &bufferID);
    if((ret = alGetError()) != AL_NO_ERROR)
    {
        printf("error alGenBuffers %x \n", ret);
        // printf("error alGenBuffers %x : %s\n", ret,alutGetErrorString (ret));
        //AL_ILLEGAL_ENUM
        //AL_INVALID_VALUE
        //#define AL_ILLEGAL_COMMAND                        0xA004
        //#define AL_INVALID_OPERATION                      0xA004
    }
    
    if (aBit == 8)
    {
        if (aChannel == 1)
        {
            format = AL_FORMAT_MONO8;
        }
        else if(aChannel == 2)
        {
            format = AL_FORMAT_STEREO8;
        }
    }
    
    if( aBit == 16 )
    {
        if( aChannel == 1 )
        {
            format = AL_FORMAT_MONO16;
        }
        if( aChannel == 2 )
        {
            format = AL_FORMAT_STEREO16;
        }
    }
    //指定要将数据复制到缓冲区中的数据
    alBufferData(bufferID, format, data, dataSize,aSampleRate);
    if((ret = alGetError()) != AL_NO_ERROR)
    {
        printf("error alBufferData %x\n", ret);
        //AL_ILLEGAL_ENUM
        //AL_INVALID_VALUE
        //#define AL_ILLEGAL_COMMAND                        0xA004
        //#define AL_INVALID_OPERATION                      0xA004
    }
    //附加一个或一组buffer到一个source上
    alSourceQueueBuffers(_sourceId, 1, &bufferID);
    if((ret = alGetError()) != AL_NO_ERROR)
    {
        printf("error alSourceQueueBuffers %x\n", ret);
    }
    
    //更新队列数据
//    ret = [self updataQueueBuffer];
//    bufferID = 0;
    
    return ret;
}

-(int)updataQueueBuffer {
    
    //播放状态字段
    ALint stateVaue = 0;
    
    //获取处理队列，得出已经播放过的缓冲器的数量
    alGetSourcei(_sourceId, AL_BUFFERS_PROCESSED, &_numprocessed);
    
    //获取缓存队列，缓存的队列数量
    alGetSourcei(_sourceId, AL_BUFFERS_QUEUED, &_numqueued);
    
    //获取播放状态，是不是正在播放
    alGetSourcei(_sourceId, AL_SOURCE_STATE, &stateVaue);
//    printf("al queue num:%d , process num:%d\n", _numqueued, _numprocessed );
    //printf("===statevaue ========================%x\n",stateVaue);
    
//    if (stateVaue == AL_STOPPED ||
//        stateVaue == AL_PAUSED ||
//        stateVaue == AL_INITIAL)
//    {
//        //如果没有数据,或数据播放完了
//        if (_numqueued < _numprocessed || _numqueued == 0 ||(_numqueued == 1 && _numprocessed ==1))
//        {
//            //停止播放
//            printf("...Audio Stop\n");
//            [self stopSound];;
//            [self destroy];
//            return 0;
//        }
//        
//        if (stateVaue != AL_PLAYING)
//        {
//            [self playSound];
//        }
//    }
    
    //将已经播放过的的数据删除掉
    while(_numprocessed --)
    {
        ALuint buff;
        //更新缓存buffer中的数据到source中
        alSourceUnqueueBuffers(_sourceId, 1, &buff);
        //删除缓存buff中的数据
        alDeleteBuffers(1, &buff);
        
        //得到已经播放的音频队列多少块
        _isplayBufferSize ++;
    }
    
    return 1;
}

-(void)playSound{
    
    int ret = 0;
    
    alSourcePlay(_sourceId);
    if((ret = alGetError()) != AL_NO_ERROR)
    {
        printf("error alcMakeContextCurrent %x\n", ret);
    }
}

-(void)stopSound{
    
    alSourceStop(_sourceId);
}

- (void)setVolume:(float)volume{
    
    _volume = volume;
    alSourcef(_sourceId,AL_GAIN,volume);
}

- (float)volume{
    return _volume;
}

-(void)setPlayRate:(double)playRate{
    
    alSourcef(_sourceId, AL_PITCH, playRate);
}

@end
