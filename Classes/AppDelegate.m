//
//  AppDelegate.h
//  MyLivePlayer
//
//  Created by GevinChen on 19/7/12.
//  Copyright (c) 2019年 GevinChen. All rights reserved.
//

#import "AppDelegate.h"
#import "ViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    window = [[UIWindow alloc]initWithFrame: [UIScreen mainScreen].bounds];
    ViewController *vc = [ViewController new];
    window.rootViewController = vc;
    [window makeKeyAndVisible];
    return YES;
}

@end
