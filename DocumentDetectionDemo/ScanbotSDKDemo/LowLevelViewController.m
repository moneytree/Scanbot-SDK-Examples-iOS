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

@property(atomic, assign) BOOL detectionEnabled;
@property (strong, nonatomic) SBSDKDocumentDetector *detector;
@property (strong, nonatomic) SBSDKImageStorage *imageStorage;
@property (strong, nonatomic) SBSDKProgress *currentProgress;
@property (nonatomic, strong) SBSDKPolygonLayer *polygonLayer;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic, strong) AVCaptureStillImageOutput *stillImageOutput;
@end

@implementation LowLevelViewController

- (SBSDKPolygonLayer *)polygonLayer {
  if (!_polygonLayer) {
    UIColor *color = [UIColor colorWithRed:0.0f green:0.5f blue:1.0f alpha:1.0f];
    _polygonLayer = [[SBSDKPolygonLayer alloc] initWithLineColor:color];
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

  self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
  NSDictionary *outputSettings = @{AVVideoCodecKey: AVVideoCodecJPEG};
  self.stillImageOutput.outputSettings = outputSettings;
  [self.session addOutput:self.stillImageOutput];

  //Preview Layer
  self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
  self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

  [self.view.layer addSublayer:self.previewLayer];
  [self.view.layer addSublayer:self.polygonLayer];
}

- (void)initializeImageStorage {
  self.imageStorage = [[SBSDKImageStorage alloc] init];
}

- (void)initializeDetector {
  self.detector = [[SBSDKDocumentDetector alloc] init];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor blackColor];

  [self initializeCameraSession];
  [self initializeImageStorage];
  [self initializeDetector];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];

  self.previewLayer.frame = self.view.bounds;
  self.polygonLayer.frame = self.view.bounds;
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  self.polygonLayer.path = nil;
  [self.session startRunning];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    self.detectionEnabled = YES;
  });
}

- (void)viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
  self.detectionEnabled = NO;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
 didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
 fromConnection:(AVCaptureConnection *)connection {
  if (!self.detectionEnabled) {
    return;
  }

  SBSDKDocumentDetectorResult *result = [self.detector detectDocumentPolygonOnSampleBuffer:sampleBuffer
    visibleImageRect:CGRectZero
    smoothingEnabled:NO
    useLiveDetectionParameters:YES];

  dispatch_async(dispatch_get_main_queue(), ^{
    self.polygonLayer.path = [result.polygon bezierPathForPreviewLayer:self.previewLayer].CGPath;
  });

  switch(result.status) {
    case SBSDKDocumentDetectionStatusOK:
      NSLog(@"Ok");
      self.detectionEnabled = NO;
      self.polygonLayer.path = nil;
      [self captureImageInPolygon:result.polygon];
      break;
    case SBSDKDocumentDetectionStatusOK_SmallSize:
      NSLog(@"Ok Small");
      self.detectionEnabled = NO;
      self.polygonLayer.path = nil;
      [self captureImageInPolygon:result.polygon];
      break;
    case SBSDKDocumentDetectionStatusOK_BadAngles:
      NSLog(@"Ok Bad Angle");
      break;
    case SBSDKDocumentDetectionStatusOK_BadAspectRatio:
      NSLog(@"Ok Bad Aspect Ratio");
      self.detectionEnabled = NO;
      self.polygonLayer.path = nil;
      [self captureImageInPolygon:result.polygon];
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

- (void)captureImageInPolygon: (SBSDKPolygon *)polygon {
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

  if (!polygon || !videoConnection) {
    return;
  }

  [self.stillImageOutput
   captureStillImageAsynchronouslyFromConnection:videoConnection
   completionHandler:^(CMSampleBufferRef sampleBuffer, NSError *error) {
    NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:sampleBuffer];
    UIImage *image = [[UIImage alloc] initWithData:imageData];
    image = [image imageRotatedCounterClockwise:1];
    image = [image imageWarpedByPolygon:polygon andFilteredBy:SBSDKImageFilterTypeBinarized];
    image = [image imageRotatedClockwise:1];
    [self.imageStorage addImage:image];
    [self writePDF];
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

@end
