//
//  ViewController.m
//  MyLivePlayer
//
//  Created by GevinChen on 19/7/12.
//  Copyright (c) 2019年 GevinChen. All rights reserved.


#import "ViewController.h"
#import "StreamingHandler.h"
#import "GLESView.h"

@interface ViewController () <VideoExtractorDelegate>
{
    StreamingHandler *streamingHandler;
}

@property (nonatomic, weak) IBOutlet UIButton *playButton;
@property (weak, nonatomic) IBOutlet UITextField *textUrl;

@end

@implementation ViewController
{
    NSThread *_thread;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // NSString *videoPath = [[NSBundle mainBundle] pathForResource:@"war3end" ofType:@"mp4"];
    self.textUrl.text = @"rtmp://172.20.10.2/live/test";
    
    [self.view bringSubviewToFront:self.textUrl];
    [self.view bringSubviewToFront:self.playButton];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
}

-(IBAction)playButtonAction:(id)sender {
    
    if ( streamingHandler.isPlaying ) {
        _playButton.selected = NO;
        [streamingHandler stop];
        streamingHandler = nil;
    }
    else{
        if (self.textUrl.text.length > 0) {
            _playButton.selected = YES;
            streamingHandler = [StreamingHandler new];
            streamingHandler.delegate = self;
            [self.view addSubview:streamingHandler.glView];
            streamingHandler.videoPath = self.textUrl.text;
            [streamingHandler start];
        }
    }
    
}

#pragma mark - VideoExtractorDelegate

- (void)videoStart
{
    
}

- (void)videoEnd
{
    _playButton.selected = NO;
}

@end
