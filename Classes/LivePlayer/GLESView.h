//
//  GLESView.h
//  MyLivePlayer
//
//  Created by GevinChen on 19/7/12.
//  Copyright (c) 2019年 GevinChen. All rights reserved.


#import <UIKit/UIKit.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/EAGLDrawable.h>
#import <OpenGLES/ES2/glext.h>
#import <OpenGLES/EAGL.h>


@interface GLESView : UIView

- (void)setupGLWithBufferSize:(CGSize)bufferSize;

- (void)displayYUV420pData:(void *)data;

- (void)render:(CADisplayLink *)displayLink;

@end
