//
//  DocumentDemoViewController.h
//  PayFormScannerDemo
//
//  Created by Sebastian Husche on 08.06.15.
//  Copyright (c) 2015 doo GmbH. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <ScanbotSDK/ScanbotSDK.h>
#import "DemoViewController.h"

@interface HighLevelViewController : DemoViewController<SBSDKScannerViewControllerDelegate>

@end
