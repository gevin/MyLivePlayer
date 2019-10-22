//
//  GLESView.m
//  MyLivePlayer
//
//  Created by GevinChen on 19/7/12.
//  Copyright (c) 2019年 GevinChen. All rights reserved.


#import "GLESView.h"

enum TextureType
{
    TEX_Y = 0,
    TEX_U = 1,
    TEX_V = 2,
};

@implementation GLESView
{
    CAEAGLLayer        *_eaglLayer;
    EAGLContext        *_eaglContext;
    GLuint              _renderbuffer;
    GLuint              _framebuffer;
    GLuint              _program;
    GLuint              _textureYUV[3];
    GLuint              _attrib_Vertex;
    GLuint              _attrib_TexCoord;
    GLuint              _videoW;
    GLuint              _videoH;
    CADisplayLink      *_displayLink;
}

+ (Class)layerClass {
    return [CAEAGLLayer class];
}

#pragma mark - OpenGL ES Setup

- (void)layoutSubviews
{
    if ( _eaglContext ) {
        @synchronized(self)
        {
            [EAGLContext setCurrentContext:_eaglContext];
            [self destoryFrameAndRenderBuffer];
            [self setupFrameBufferRenderBuffer];
        }
        
        glViewport(0, 0, self.bounds.size.width, self.bounds.size.height);
    }
}

- (void)setupGLWithBufferSize:(CGSize)bufferSize
{
    
    [self setupContext];
    
    [self setupYUVTexture];
    
    [self setupTextureSize:bufferSize];
    
    [self setupShaders];

}

- (void)setupContext
{
    _eaglLayer = (CAEAGLLayer*) self.layer;
    
    _eaglLayer.opaque = YES;
    _eaglLayer.drawableProperties = @{kEAGLDrawablePropertyRetainedBacking:@(NO),
                                      kEAGLDrawablePropertyColorFormat:kEAGLColorFormatRGBA8};
    _eaglContext = [[EAGLContext alloc] initWithAPI: kEAGLRenderingAPIOpenGLES2 ];
    if (!_eaglContext) {
        NSLog(@"Failed to initialize OpenGLES 2.0 context");
        exit(1);
    }
    if (![EAGLContext setCurrentContext: _eaglContext ]) {
        NSLog(@"Failed to set current OpenGL context");
        exit(1);
    }
    
}

- (void)setupFrameBufferRenderBuffer
{
    glGenFramebuffers(1, &_framebuffer);
    glGenRenderbuffers( 1, &_renderbuffer );
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    glBindRenderbuffer( GL_RENDERBUFFER, _renderbuffer );
    
    if (![_eaglContext renderbufferStorage:GL_RENDERBUFFER fromDrawable: _eaglLayer ]){
        NSLog(@"dispatch renderbuffer fail.");
    }
    
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _renderbuffer );
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE){
        NSLog(@"attach renderbuffer fail. 0x%x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }
}

- (void)destoryFrameAndRenderBuffer
{
    if (_framebuffer){
        glDeleteFramebuffers(1, &_framebuffer);
    }
    
    if (_renderbuffer){
        glDeleteRenderbuffers(1, &_renderbuffer);
    }
    
    _framebuffer = 0;
    _renderbuffer = 0;
}

- (void)setupShaders
{
    GLuint verShader, fragShader;
    
    NSString* vertShaderPathname = [[NSBundle mainBundle] pathForResource:@"shaderv" ofType:@"vsh"];
    NSString* fragShaderPathname = [[NSBundle mainBundle] pathForResource:@"shaderf" ofType:@"fsh"];
    
    if (![self compileShader:&verShader type:GL_VERTEX_SHADER file:vertShaderPathname]) {
        NSLog(@"Failed to compile vertex shader");
        return ;
    }
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:fragShaderPathname]) {
        NSLog(@"Failed to compile fragment shader");
        return ;
    }

    _program = glCreateProgram();
    glAttachShader(_program, verShader);
    glAttachShader(_program, fragShader);
    
    if(verShader)
        glDeleteShader(verShader);
    if(fragShader)
        glDeleteShader(fragShader);
    
    // link program
    glLinkProgram(_program);
    GLint linkSuccess;
    glGetProgramiv(_program, GL_LINK_STATUS, &linkSuccess);
    if (linkSuccess == GL_FALSE) {
        GLchar messages[256];
        glGetProgramInfoLog(_program, sizeof(messages), 0, &messages[0]);
        NSString *messageString = [NSString stringWithUTF8String:messages];
        NSLog(@"error%@", messageString);
        return ;
    }
    
    glUseProgram(_program);
    
    _attrib_Vertex = glGetAttribLocation(_program, "position");
    _attrib_TexCoord = glGetAttribLocation(_program, "TexCoordIn");
    
    GLuint textureUniformY = glGetUniformLocation(_program, "SamplerY");
    GLuint textureUniformU = glGetUniformLocation(_program, "SamplerU");
    GLuint textureUniformV = glGetUniformLocation(_program, "SamplerV");
    
    glUniform1i(textureUniformY, 0); // SamplerY = 0
    glUniform1i(textureUniformU, 1); // SamplerU = 1
    glUniform1i(textureUniformV, 2); // SamplerV = 2
    
    static const GLfloat squareVertices[] = {
        -1.0f, -1.0f,
        1.0f, -1.0f,
        -1.0f,  1.0f,
        1.0f,  1.0f,
    };
    
    
    static const GLfloat coordVertices[] = {
        0.0f, 1.0f,
        1.0f, 1.0f,
        0.0f,  0.0f,
        1.0f,  0.0f,
    };
    
    // Update attribute values
    glVertexAttribPointer( _attrib_Vertex, 2, GL_FLOAT, 0, 0, squareVertices);
    glEnableVertexAttribArray(_attrib_Vertex);
    
    glVertexAttribPointer(_attrib_TexCoord, 2, GL_FLOAT, 0, 0, coordVertices);
    glEnableVertexAttribArray( _attrib_TexCoord );
}


- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file
{
    GLint status;
    const GLchar *source;
    
    source = (GLchar *)[[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] UTF8String];
    if (!source) {
        NSLog(@"Failed to load vertex shader");
        return NO;
    }
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    

    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (void)setupYUVTexture
{
    if (_textureYUV[TEX_Y]){
        glDeleteTextures(3, _textureYUV );
    }
    glGenTextures(3, _textureYUV );
    if (!_textureYUV[TEX_Y] || !_textureYUV[TEX_U] || !_textureYUV[TEX_V]){
        return;
    }
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _textureYUV[TEX_Y]);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, _textureYUV[TEX_U]);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_2D, _textureYUV[TEX_V]);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}


- (void)setupTextureSize:(CGSize)size
{
    _videoW = size.width;
    _videoH = size.height;
    void *blackData = malloc(size.width * size.height * 1.5);
    if(blackData)
        memset(blackData, 0x0, size.width * size.height * 1.5);
    
    [EAGLContext setCurrentContext:_eaglContext];
    glBindTexture(GL_TEXTURE_2D, _textureYUV[TEX_Y]);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED_EXT, size.width, size.height, 0, GL_RED_EXT, GL_UNSIGNED_BYTE, blackData);
    
    glBindTexture(GL_TEXTURE_2D, _textureYUV[TEX_U]);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED_EXT, size.width/2, size.height/2, 0, GL_RED_EXT, GL_UNSIGNED_BYTE, blackData + (int)(size.width * size.height) );
    
    glBindTexture(GL_TEXTURE_2D, _textureYUV[TEX_V]);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED_EXT, size.width/2, size.height/2, 0, GL_RED_EXT, GL_UNSIGNED_BYTE, blackData + (int)(size.width * size.height) * 5 / 4);
    free(blackData);
    
}

- (void)displayYUV420pData:(void *)data
{
    [EAGLContext setCurrentContext:_eaglContext];
    
    glBindTexture(GL_TEXTURE_2D, _textureYUV[TEX_Y]);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, _videoW, _videoH, GL_RED_EXT, GL_UNSIGNED_BYTE, data);
    
    glBindTexture(GL_TEXTURE_2D, _textureYUV[TEX_U]);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, _videoW/2, _videoH/2, GL_RED_EXT, GL_UNSIGNED_BYTE, data + _videoW * _videoH);
    
    glBindTexture(GL_TEXTURE_2D, _textureYUV[TEX_V]);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, _videoW/2, _videoH/2, GL_RED_EXT, GL_UNSIGNED_BYTE, data + _videoW * _videoH * 5 / 4);
}

- (void)render:(CADisplayLink *)displayLink
{
    
    [EAGLContext setCurrentContext:_eaglContext];
    
    CGSize size = self.bounds.size;
    glViewport(0, 0, size.width, size.height);
    
    glClearColor(0, 0, 0, 1.0f);
    glClear( GL_COLOR_BUFFER_BIT );
    
    glUseProgram(_program);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
    [_eaglContext presentRenderbuffer:GL_RENDERBUFFER];
}

@end
