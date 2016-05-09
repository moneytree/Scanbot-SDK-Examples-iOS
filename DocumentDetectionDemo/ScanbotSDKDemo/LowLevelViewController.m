//
//  PayformDemoViewController.m
//  ScanbotSDKDemo
//
//  Created by Sebastian Husche on 17.02.16.
//  Copyright © 2016 doo GmbH. All rights reserved.
//

@import ImageIO;

#import "LowLevelViewController.h"
#import "PDFViewController.h"

@interface LowLevelViewController () <SBSDKCameraSessionDelegate>

@property (atomic, assign) BOOL detectionEnabled;
@property (strong, nonatomic) SBSDKDocumentDetector *detector;
@property (strong, nonatomic) SBSDKImageStorage *imageStorage;
@property (strong, nonatomic) SBSDKProgress *currentProgress;
@property (nonatomic, strong) CAShapeLayer *polygonLayer;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic, strong) AVCaptureStillImageOutput *stillImageOutput;
@property (nonatomic, strong) UIImageView *imageView;

@property (nonatomic, strong) UIButton *takePhotoButton;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *scanAnotherButton;

@property (nonatomic, strong) UIView *topLeftCornerView;
@property (nonatomic, strong) UIView *topRightCornerView;
@property (nonatomic, strong) UIView *bottomLeftCornerView;
@property (nonatomic, strong) UIView *bottomRightCornerView;

@property (nonatomic, strong) SBSDKPolygon *detectedPolygon;

@end

void getPoints(void *info, const CGPathElement *element)
{
    NSMutableArray *bezierPoints = (__bridge NSMutableArray *)info;
    CGPathElementType type = element->type;
    CGPoint *points = element->points;
    if (type != kCGPathElementCloseSubpath) {
      if ((type == kCGPathElementAddLineToPoint) || (type == kCGPathElementMoveToPoint)) {
        [bezierPoints addObject:[NSValue valueWithCGPoint:points[0]]];
      } else if (type == kCGPathElementAddQuadCurveToPoint) {
        [bezierPoints addObject:[NSValue valueWithCGPoint:points[1]]];
      } else if (type == kCGPathElementAddCurveToPoint) {
        [bezierPoints addObject:[NSValue valueWithCGPoint:points[2]]];
      }
    }
}

@implementation LowLevelViewController

- (CAShapeLayer *)polygonLayer {
  if (!_polygonLayer) {
    UIColor *color = [UIColor colorWithRed:0.0f green:0.5f blue:1.0f alpha:1.0f];
    _polygonLayer = [[CAShapeLayer alloc] init];
    _polygonLayer.strokeColor = color.CGColor;
    _polygonLayer.fillColor = [UIColor colorWithRed:0.0f green:0.55f blue:1.0f alpha:0.5f].CGColor;
  }
  return _polygonLayer;
}

- (void)initializeCameraSession {
  self.session = [[AVCaptureSession alloc]init];
  self.session.sessionPreset = AVCaptureSessionPresetPhoto;

  AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
  AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];

  if (!input) {
    NSLog(@"No Input");
    return;
  }

  [self.session addInput:input];

  //Output
  dispatch_queue_t dispatchQueue;
  dispatchQueue = dispatch_queue_create("scannerQueue", NULL);

  self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
  [self.session addOutput:self.videoDataOutput];
  [self.videoDataOutput setSampleBufferDelegate:self queue:dispatchQueue];
  self.videoDataOutput.videoSettings = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
//
  AVCaptureConnection *connection = [self.videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
  if ([connection isVideoOrientationSupported]) {
    [connection setVideoOrientation: AVCaptureVideoOrientationPortrait];
  }

  self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
  NSDictionary *outputSettings = @{AVVideoCodecKey: AVVideoCodecJPEG};
  self.stillImageOutput.outputSettings = outputSettings;

  [self.session addOutput:self.stillImageOutput];

  //Preview Layer
  self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
  self.previewLayer.videoGravity = AVLayerVideoGravityResize;
  [self.view.layer addSublayer:self.previewLayer];

  self.imageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
  self.imageView.contentMode = UIViewContentModeScaleToFill;
  self.imageView.hidden = true;
  [self.view addSubview:self.imageView];

  [self.view.layer addSublayer:self.polygonLayer];

  self.topLeftCornerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
  self.topLeftCornerView.backgroundColor = [UIColor redColor];
  [self.topLeftCornerView addGestureRecognizer:[[UIPanGestureRecognizer alloc]
    initWithTarget:self
    action:@selector(cornerPanGestureRecognized:)]];
  self.topLeftCornerView.hidden = true;

  self.topRightCornerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
  self.topRightCornerView.backgroundColor = [UIColor redColor];
  [self.topRightCornerView addGestureRecognizer:[[UIPanGestureRecognizer alloc]
    initWithTarget:self
    action:@selector(cornerPanGestureRecognized:)]];
  self.topRightCornerView.hidden = true;

  self.bottomLeftCornerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
  self.bottomLeftCornerView.backgroundColor = [UIColor redColor];
  [self.bottomLeftCornerView addGestureRecognizer:[[UIPanGestureRecognizer alloc]
    initWithTarget:self
    action:@selector(cornerPanGestureRecognized:)]];
  self.bottomLeftCornerView.hidden = true;

  self.bottomRightCornerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
  self.bottomRightCornerView.backgroundColor = [UIColor redColor];
  [self.bottomRightCornerView addGestureRecognizer:[[UIPanGestureRecognizer alloc]
    initWithTarget:self
    action:@selector(cornerPanGestureRecognized:)]];
  self.bottomRightCornerView.hidden = true;

  [self.view addSubview:self.topLeftCornerView];
  [self.view addSubview:self.topRightCornerView];
  [self.view addSubview:self.bottomLeftCornerView];
  [self.view addSubview:self.bottomRightCornerView];
}

- (void)initializeImageStorage {
  self.imageStorage = [[SBSDKImageStorage alloc] init];
}

- (void)initializeDetector {
  self.detector = [[SBSDKDocumentDetector alloc] init];
}

- (void)initializeTakePhotoButton {
  self.takePhotoButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.takePhotoButton setTitle:@"Take Photo" forState:UIControlStateNormal];
  [self.takePhotoButton
    addTarget:self
    action:@selector(takePhotoButtonPressed:)
    forControlEvents:UIControlEventTouchUpInside
  ];
  [self.view addSubview:self.takePhotoButton];
  self.takePhotoButton.frame = CGRectMake(self.view.center.x - 50, self.view.bounds.size.height - 44, 100, 44);
  self.takePhotoButton.hidden = true;
}

- (void)initializeRetryButton {
  self.retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.retryButton setTitle:@"Retry" forState:UIControlStateNormal];
  [self.retryButton
    addTarget:self
    action:@selector(retryButtonPressed:)
    forControlEvents:UIControlEventTouchUpInside
  ];
  [self.view addSubview:self.retryButton];
  self.retryButton.frame = CGRectMake(self.view.frame.origin.x + 20, self.view.bounds.size.height - 44, 100, 44);
  self.retryButton.hidden = true;
}

- (void)initializeSaveButton {
  self.saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.saveButton setTitle:@"Save" forState:UIControlStateNormal];
  [self.saveButton
    addTarget:self
    action:@selector(saveButtonPressed:)
    forControlEvents:UIControlEventTouchUpInside
  ];
  [self.view addSubview:self.saveButton];
  self.saveButton.frame = CGRectMake(self.view.center.x - 50, self.view.bounds.size.height - 44, 100, 44);
  self.saveButton.hidden = true;
}

- (void)initializeScanAnotherButton {
  self.scanAnotherButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.scanAnotherButton setTitle:@"Scan Another" forState:UIControlStateNormal];
  [self.scanAnotherButton
    addTarget:self
    action:@selector(scanAnotherButtonPressed:)
    forControlEvents:UIControlEventTouchUpInside
  ];
  [self.view addSubview:self.scanAnotherButton];
  self.scanAnotherButton.frame = CGRectMake(self.view.frame.size.width - 120, self.view.bounds.size.height - 44, 100, 44);
  self.scanAnotherButton.hidden = true;
}


- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor blackColor];

  [self initializeCameraSession];
  [self initializeImageStorage];
  [self initializeDetector];
  [self initializeTakePhotoButton];
  [self initializeRetryButton];
  [self initializeSaveButton];
  [self initializeScanAnotherButton];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];

  self.previewLayer.frame = self.view.bounds;
  self.polygonLayer.frame = self.view.bounds;
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self.session startRunning];
  [self transitionToA];
}

- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
  [self.session stopRunning];
  self.detectionEnabled = NO;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
 didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
 fromConnection:(AVCaptureConnection *)connection {
  if (!self.detectionEnabled) {
    return;
  }

  CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  CIImage *cameraImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];

  CIFilter *filter = [CIFilter filterWithName:@"YUCISurfaceBlur"];
  [filter setValue:@(3.0) forKey:@"inputRadius"];
  [filter setValue:@(5.0) forKey:@"inputThreshold"];
  [filter setValue:cameraImage forKey:kCIInputImageKey];

  UIImage *image = [UIImage imageWithCIImage:cameraImage];

  SBSDKDocumentDetectorResult *result = [self.detector
    detectDocumentPolygonOnImage:image
    visibleImageRect:CGRectZero
    smoothingEnabled:NO
    useLiveDetectionParameters:YES
  ];

  dispatch_async(dispatch_get_main_queue(), ^{
    self.polygonLayer.path = [result.polygon bezierPathForSize:self.imageView.bounds.size].CGPath;
  });

  switch(result.status) {
    case SBSDKDocumentDetectionStatusOK:
      NSLog(@"Ok");
      self.detectedPolygon = result.polygon;
      [self transitionToB];
      break;
    case SBSDKDocumentDetectionStatusOK_SmallSize:
      NSLog(@"Ok Small");
      self.detectedPolygon = result.polygon;
      [self transitionToB];
      break;
    case SBSDKDocumentDetectionStatusOK_BadAngles:
      NSLog(@"Ok Bad Angle");
      break;
    case SBSDKDocumentDetectionStatusOK_BadAspectRatio:
      NSLog(@"Ok Bad Aspect Ratio");
      self.detectedPolygon = result.polygon;
      [self transitionToB];
      break;
    case SBSDKDocumentDetectionStatusError_NothingDetected:
      NSLog(@"Error nothing detected");
      break;
    case SBSDKDocumentDetectionStatusError_Brightness:
      NSLog(@"Error brightness");
      break;
    case SBSDKDocumentDetectionStatusError_Noise:
      NSLog(@"Error noise");
      break;
  }
}

- (void)transitionToA {
  self.polygonLayer.path = nil;
  self.imageView.hidden = true;
  self.previewLayer.connection.enabled = YES;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.detectionEnabled = YES;
    self.retryButton.hidden = true;
    self.saveButton.hidden = true;
    self.scanAnotherButton.hidden = true;
  });
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (self.detectionEnabled) {
      self.takePhotoButton.hidden = false;
    }
  });
}

- (void)transitionToB {
  self.detectionEnabled = NO;
  self.previewLayer.connection.enabled = NO;
  self.imageView.hidden = false;
  [self captureImage];
  dispatch_async(dispatch_get_main_queue(), ^{
    [self showCornerControls:self.detectedPolygon];
    self.takePhotoButton.hidden = true;
    self.retryButton.hidden = false;
    self.saveButton.hidden = false;
    self.scanAnotherButton.hidden = false;
  });
}

- (void)transitionToC {
  UIImage *image = [self.imageView.image
    imageWarpedByPolygon:self.detectedPolygon
    andFilteredBy:SBSDKImageFilterTypeBinarized];
  [self.imageStorage addImage:image];
  [self writePDF];
}

- (void)captureImage {
  AVCaptureConnection *videoConnection = nil;

  for (AVCaptureConnection *connection in self.stillImageOutput.connections) {
    for (AVCaptureInputPort *port in [connection inputPorts]) {
        if ([[port mediaType] isEqual:AVMediaTypeVideo] ) {
          videoConnection = connection;
          break;
        }
    }
    if (videoConnection) { break; }
  }

  if (!videoConnection) {
    return;
  }

  [self.stillImageOutput
   captureStillImageAsynchronouslyFromConnection:videoConnection
   completionHandler:^(CMSampleBufferRef sampleBuffer, NSError *error) {
    NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:sampleBuffer];
    UIImage *image = [[UIImage alloc] initWithData:imageData];
    self.imageView.image = image;
  }];
}

- (void)writePDF {
  NSString *filename = @"ScanbotSDK_PDF.pdf";
  NSURL *pdfURL = [SBSDKImageStorage applicationDocumentsFolderURL];
  pdfURL = [pdfURL URLByAppendingPathComponent:filename];

  self.currentProgress = [SBSDKPDFRenderer
   renderImageStorage:self.imageStorage
   copyImageStorage:YES
   indexSet:nil
   withPageSize:SBSDKPDFRendererPageSizeFromImage
   output:pdfURL
   completionHandler:^(BOOL finished, NSError *error, NSDictionary *resultInfo) {
    if (finished && error == nil) {
      NSURL *outputURL = resultInfo[SBSDKResultInfoDestinationFileURLKey];
      PDFViewController *pdfController = [PDFViewController pdfControllerWithURL:outputURL];
      [self.navigationController pushViewController:pdfController animated:YES];
    } else {
      NSLog(@"%@", error);
    }
    self.currentProgress = nil;
  }];
}

- (void)takePhotoButtonPressed:(UIButton*)button {
  [self captureImage];
  [self transitionToB];
}

- (void)retryButtonPressed:(UIButton*)button {
  [self transitionToA];
}

- (void)saveButtonPressed:(UIButton*)button {
  [self transitionToC];
}

- (void)scanAnotherButtonPressed:(UIButton*)button {
  [self transitionToA];
}

- (void)showCornerControls:(SBSDKPolygon*)polygon {
  NSMutableArray *points = [NSMutableArray array];
  CGPathApply(
    [self.detectedPolygon bezierPathForSize:self.imageView.bounds.size].CGPath,
    (__bridge void *)points,
    getPoints
  );

  CGPoint topLeftCorner = ((NSValue*) points[0]).CGPointValue;
  self.topLeftCornerView.center = topLeftCorner;
  self.topLeftCornerView.hidden = false;

  CGPoint topRightCorner = ((NSValue*) points[1]).CGPointValue;
  self.topRightCornerView.center = topRightCorner;
  self.topRightCornerView.hidden = false;

  CGPoint bottomLeftCorner = ((NSValue*) points[3]).CGPointValue;
  self.bottomLeftCornerView.center = bottomLeftCorner;
  self.bottomLeftCornerView.hidden = false;

  CGPoint bottomRightCorner = ((NSValue*) points[2]).CGPointValue;
  self.bottomRightCornerView.center = bottomRightCorner;
  self.bottomRightCornerView.hidden = false;
}

- (void)cornerPanGestureRecognized:(UIPanGestureRecognizer *)panGestureRecognizer {
  CGPoint normalizedPoint = CGPointMake(
    [panGestureRecognizer locationInView:self.view].x / self.view.bounds.size.width,
    [panGestureRecognizer locationInView:self.view].y / self.view.bounds.size.height
  );
  if (panGestureRecognizer.view == self.topLeftCornerView) {
    self.detectedPolygon = [[SBSDKPolygon alloc]
      initWithNormalizedPointA: normalizedPoint
      pointB: [self.detectedPolygon normalizedPointWithIndex:1]
      pointC: [self.detectedPolygon normalizedPointWithIndex:2]
      pointD: [self.detectedPolygon normalizedPointWithIndex:3]
    ];
  } else if (panGestureRecognizer.view == self.topRightCornerView) {
    self.detectedPolygon = [[SBSDKPolygon alloc]
      initWithNormalizedPointA: [self.detectedPolygon normalizedPointWithIndex:0]
      pointB: normalizedPoint
      pointC: [self.detectedPolygon normalizedPointWithIndex:2]
      pointD: [self.detectedPolygon normalizedPointWithIndex:3]
    ];
  } else if (panGestureRecognizer.view == self.bottomRightCornerView) {
    self.detectedPolygon = [[SBSDKPolygon alloc]
      initWithNormalizedPointA: [self.detectedPolygon normalizedPointWithIndex:0]
      pointB: [self.detectedPolygon normalizedPointWithIndex:1]
      pointC: normalizedPoint
      pointD: [self.detectedPolygon normalizedPointWithIndex:3]
    ];
  } else if (panGestureRecognizer.view == self.bottomLeftCornerView) {
    self.detectedPolygon = [[SBSDKPolygon alloc]
      initWithNormalizedPointA: [self.detectedPolygon normalizedPointWithIndex:0]
      pointB: [self.detectedPolygon normalizedPointWithIndex:1]
      pointC: [self.detectedPolygon normalizedPointWithIndex:2]
      pointD: normalizedPoint
    ];
  }

  self.polygonLayer.path = [self.detectedPolygon bezierPathForSize:self.imageView.bounds.size].CGPath;
  [self showCornerControls:self.detectedPolygon];
}

@end