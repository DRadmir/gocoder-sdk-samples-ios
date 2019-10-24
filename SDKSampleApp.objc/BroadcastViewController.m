//
//  BroadcastViewController.m
//  SDKSampleApp
//
//  This code and all components © 2015 – 2019 Wowza Media Systems, LLC. All rights reserved.
//  This code is licensed pursuant to the BSD 3-Clause License.
//


#import <WowzaGoCoderSDK/WowzaGoCoderSDK.h>

#import "BroadcastViewController.h"
#import "SettingsViewModel.h"
#import "SettingsViewController.h"
#import "MP4Writer.h"


#pragma mark VideoPlayerViewController (GoCoder SDK Sample App) -

NSString *const SDKSampleSavedConfigKey = @"SDKSampleSavedConfigKey";
//NSString *const SDKSampleAppLicenseKey = @"GOSK-6443-0101-CD19-EB0F-E04E"; //old-no-features

//USE NEW KEY
NSString *const SDKSampleAppLicenseKey = @"GOSK-4144-010C-A3FA-1EA0-832F"; // com.wowza.gocoder.sdk.bpsampleapp


@interface BroadcastViewController () <WOWZBroadcastStatusCallback, WOWZVideoSink, WOWZAudioSink, WOWZVideoEncoderSink, WOWZAudioEncoderSink, WOWZDataSink, UIGestureRecognizerDelegate>

#pragma mark - UI Elements
@property (nonatomic, weak) IBOutlet UIButton           *broadcastButton;
@property (nonatomic, weak) IBOutlet UIButton           *settingsButton;
@property (nonatomic, weak) IBOutlet UIButton           *switchCameraButton;
@property (nonatomic, weak) IBOutlet UIButton           *torchButton;
@property (nonatomic, weak) IBOutlet UIButton           *micButton;
@property (nonatomic, weak) IBOutlet UIButton           *closeButton;
@property (nonatomic, weak) IBOutlet UIImageView        *bitmapOverlayImgView;
@property (weak, nonatomic) IBOutlet UILabel            *timeLabel;
@property (weak, nonatomic) IBOutlet UIButton           *pingButton;
@property (weak, nonatomic) IBOutlet UILabel            *bitrateLabel;
@property (nonatomic, weak) IBOutlet UISlider           *zoomSlider;


#pragma mark - GoCoder SDK Components
@property (nonatomic, strong) WowzaGoCoder      *goCoder;
@property (nonatomic, strong) WowzaConfig       *goCoderConfig;
@property (nonatomic, strong) WOWZCameraPreview   *goCoderCameraPreview;

#pragma mark - Data
@property (nonatomic, strong) NSMutableArray    *receivedGoCoderEventCodes;
@property (nonatomic, assign) BOOL              blackAndWhiteVideoEffect;
@property (nonatomic, assign) BOOL              bitMapOverlayEffect;
@property (nonatomic, assign) BOOL              recordVideoLocally;
@property (nonatomic, assign) CMTime            broadcastStartTime;

#pragma mark - MP4Writing
@property (nonatomic, strong) MP4Writer         *mp4Writer;
@property (nonatomic, assign) BOOL              writeMP4;
@property (nonatomic, strong) dispatch_queue_t  video_capture_queue;

#pragma mark - WOWZData injection
@property (nonatomic, assign) long long         broadcastFrameCount;

@end

#pragma mark -
@implementation BroadcastViewController

#pragma mark - UIViewController Protocol Instance Methods

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSLog(@"VideoPlayerViewController - goodbye");
}

- (void) viewDidLoad {
    [super viewDidLoad];
    
    
    self.blackAndWhiteVideoEffect = [[NSUserDefaults standardUserDefaults] boolForKey:BlackAndWhiteKey];
    self.bitMapOverlayEffect = [[NSUserDefaults standardUserDefaults] boolForKey:BitmapOverlayKey];
    self.recordVideoLocally = [[NSUserDefaults standardUserDefaults] boolForKey:RecordVideoLocallyKey];
    self.broadcastStartTime = kCMTimeInvalid;
    self.timeLabel.hidden = YES;
    
    
    self.receivedGoCoderEventCodes = [NSMutableArray new];
    
    self.zoomSlider.value = 0;



    
    // Load or initialization the streaming configuration settings
    NSData *savedConfig = [[NSUserDefaults standardUserDefaults] objectForKey:SDKSampleSavedConfigKey];
    if (savedConfig) {
        self.goCoderConfig = [NSKeyedUnarchiver unarchiveObjectWithData:savedConfig];
    }
    else {
        self.goCoderConfig = [WowzaConfig new];
    }
            
    
    NSLog(@"WowzaGoCoderSDK version:%lu.:%lu.%lu:%lu short:%@ verbose:%@",(unsigned long)[WOWZVersionInfo majorVersion],(unsigned long)[WOWZVersionInfo minorVersion],(unsigned long)[WOWZVersionInfo revision],(unsigned long)[WOWZVersionInfo buildNumber],[WOWZVersionInfo string],[WOWZVersionInfo verboseString]);
    
    NSLog(@"Platform:%@",[WOWZPlatformInfo string]);

    self.goCoder = nil;
    
    // Register the GoCoder SDK license key
    NSError *const goCoderLicensingError = [WowzaGoCoder registerLicenseKey:SDKSampleAppLicenseKey];
    if (goCoderLicensingError != nil) {
        // Handle license key registration failure
        dispatch_async(dispatch_get_main_queue(), ^{

        [BroadcastViewController showAlertWithTitle:@"GoCoder SDK Licensing Error" error:goCoderLicensingError presenter:self];
        });
        
        [self.broadcastButton setEnabled:NO];
    }
    else {
        // Initialize the GoCoder SDK
        self.goCoder = [WowzaGoCoder sharedInstance];

        // Specify the view in which to display the camera preview
        if (self.goCoder != nil) {
            
            // Request camera and microphone permissions
            [WowzaGoCoder requestPermissionForType:WowzaGoCoderPermissionTypeCamera response:^(WowzaGoCoderCapturePermission permission) {
                NSLog(@"Camera permission is: %@", permission == WowzaGoCoderCapturePermissionAuthorized ? @"authorized" : @"denied");
            }];
            
            [WowzaGoCoder requestPermissionForType:WowzaGoCoderPermissionTypeMicrophone response:^(WowzaGoCoderCapturePermission permission) {
                NSLog(@"Microphone permission is: %@", permission == WowzaGoCoderCapturePermissionAuthorized ? @"authorized" : @"denied");
            }];
            
            [self.goCoder registerVideoSink:self];
            [self.goCoder registerAudioSink:self];
            [self.goCoder registerVideoEncoderSink:self];
            [self.goCoder registerAudioEncoderSink:self];
            
            [self.goCoder registerDataSink:self eventName:@"onTextData"];
					
					  self.goCoderConfig.videoEnabled = YES;
					  self.goCoderConfig.audioEnabled = YES;
					
            self.goCoder.config = self.goCoderConfig;
					

            self.goCoder.cameraView = self.view;
            
            // Start the camera preview
            self.goCoderCameraPreview = self.goCoder.cameraPreview;
            [self.goCoderCameraPreview startPreview];
        }

        // Update the UI controls
        [self updateUIControls];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orientationChanged:) name:UIDeviceOrientationDidChangeNotification object:[UIDevice currentDevice]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(broadcastBitrateUpdated:) name:@"WOWZBroadcastBitrateNetworkThroughputUpdate" object:nil];

}

- (void) viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    self.goCoder.cameraPreview.previewLayer.frame = self.view.bounds;
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    NSData *savedConfigData = [NSKeyedArchiver archivedDataWithRootObject:self.goCoderConfig];
    [[NSUserDefaults standardUserDefaults] setObject:savedConfigData forKey:SDKSampleSavedConfigKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // Update the configuration settings in the GoCoder SDK
    if (self.goCoder != nil)
        self.goCoder.config = self.goCoderConfig;
	
	
    self.blackAndWhiteVideoEffect = [[NSUserDefaults standardUserDefaults] boolForKey:BlackAndWhiteKey];
    self.bitMapOverlayEffect = [[NSUserDefaults standardUserDefaults] boolForKey:BitmapOverlayKey];
    self.recordVideoLocally = [[NSUserDefaults standardUserDefaults] boolForKey:RecordVideoLocallyKey];
	
	// Update the UI controls
	[self updateUIControls];

}

- (void) didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (BOOL) prefersStatusBarHidden {
    return YES;
}

#pragma mark - UI Action Methods
- (IBAction) didChangeZoom:(id)sender {
    //UISlider *const slider = (UISlider *)sender;
    //WOWZCamera *const c = [self.goCoderCameraPreview camera];
    //c.zoom = slider.value;
}


- (IBAction) didTapBroadcastButton:(id)sender {

    // Ensure the minimum set of configuration settings have been specified necessary to
    // initiate a broadcast streaming session
    NSError *configError = [self.goCoder.config validateForBroadcast];
    if (configError != nil) {
        [BroadcastViewController showAlertWithTitle:@"Incomplete Streaming Settings" error:configError presenter:self];
        return;
    }
    
    // Disable the U/I controls
    dispatch_async(dispatch_get_main_queue(), ^{
        self.broadcastButton.enabled    = NO;
        self.torchButton.enabled        = NO;
        self.switchCameraButton.enabled = NO;
        self.settingsButton.enabled     = NO;
        self.closeButton.enabled        = NO;
    });
    
    if (self.goCoder.status.state == WOWZBroadcastStateBroadcasting) {
        [self.goCoder endStreaming:self];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        self.bitrateLabel.text = @"0.0 kbps";

    }
    else {
        [self.receivedGoCoderEventCodes removeAllObjects];
        [self.goCoder startStreaming:self];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.micButton setImage:[UIImage imageNamed:(self.goCoder.isAudioMuted ? @"mic_off_button" : @"mic_on_button")] forState:UIControlStateNormal];
            [UIApplication sharedApplication].idleTimerDisabled = YES;
        });
    }
}

- (IBAction) didTapSwitchCameraButton:(id)sender {
    WOWZCamera *otherCamera = [self.goCoderCameraPreview otherCamera];
    if (![otherCamera supportsWidth:self.goCoderConfig.videoWidth]) {
        [self.goCoderConfig loadPreset:otherCamera.supportedPresetConfigs.lastObject.toPreset];
        self.goCoder.config = self.goCoderConfig;
    }
    [self.goCoderCameraPreview switchCamera];
    [self.torchButton  setImage:[UIImage imageNamed:@"torch_on_button"] forState:UIControlStateNormal];
    [self updateUIControls];
}

- (IBAction) didTapTorchButton:(id)sender {
    BOOL newTorchOnState = !self.goCoderCameraPreview.camera.torchOn;
    
    self.goCoderCameraPreview.camera.torchOn = newTorchOnState;
    [self.torchButton setImage:[UIImage imageNamed:(newTorchOnState ? @"torch_off_button" : @"torch_on_button")] forState:UIControlStateNormal];
}

- (IBAction) didTapMicButton:(id)sender {
    BOOL newMutedState = !self.goCoder.isAudioMuted;
    
    self.goCoder.audioMuted = newMutedState;
    [self.micButton setImage:[UIImage imageNamed:(newMutedState ? @"mic_off_button" : @"mic_on_button")] forState:UIControlStateNormal];
}

- (IBAction) didTapSettingsButton:(id)sender {
    
    UIViewController *settingsNavigationController = [[UIStoryboard storyboardWithName:@"GoCoderSettings" bundle:nil] instantiateViewControllerWithIdentifier:@"settingsNavigationController"];
    
    SettingsViewController *settingsVC = (SettingsViewController *)(((UINavigationController *)settingsNavigationController).topViewController);
    [settingsVC addAllSections];
    
    SettingsViewModel *settingsModel = [[SettingsViewModel alloc] initWithSessionConfig:self.goCoderConfig];
    settingsModel.supportedPresetConfigs = self.goCoder.cameraPreview.camera.supportedPresetConfigs;
    settingsVC.viewModel = settingsModel;
    
    [self presentViewController:settingsNavigationController animated:YES completion:NULL];
}

- (IBAction) didTapCloseButton:(id)sender {
    [self.goCoderCameraPreview stopPreview];
    self.goCoder.cameraView = nil;
    [self.goCoder unregisterVideoSink:self];
    [self.goCoder unregisterAudioSink:self];
    [self.goCoder unregisterVideoEncoderSink:self];
    [self.goCoder unregisterAudioEncoderSink:self];
    [self.goCoder unregisterDataSink:self eventName:@"onTextData"];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction) didTapPingButton:(id)sender {
    /*
     The "Ping" button exists in order to demonstrate making a server function call; in this case, the call
     is "onGetPingTime". The server module that implements "onGetPingTime" must exist in order to receive
     a callback.
    */
    if (self.goCoder.status.state == WOWZBroadcastStateBroadcasting) {
        [self.goCoder sendPingRequest:^(WOWZDataMap * _Nullable result, BOOL isError) {
            if (!isError && result) {
                WOWZDataItem *item = [result.data valueForKey:@"responseTime"];
                if (item) {
                    NSLog(@"sendPingRequest result - ping time = %0.2f", item.doubleValue);
                }
            }
        }];
/*
        WOWZDataMap *params = [WOWZDataMap new];
        [self.goCoder sendDataEvent:WOWZDataScopeModule eventName:@"onGetPingTime" params:params callback:^(WOWZDataMap * _Nullable result, BOOL isError) {
            if (!isError && result) {
                WOWZDataItem *item = [result.data valueForKey:@"pingTime"];
                if (item) {
                    NSLog(@"onGetPingTime result - ping time = %0.2f", item.doubleValue);
                }
            }
        }];
*/
    }
}


- (BOOL)shouldAutorotate {
	return YES;
}

-(UIInterfaceOrientationMask)supportedInterfaceOrientations{
	return UIInterfaceOrientationMaskAll;
}

#pragma mark - Notifications

-(void) broadcastBitrateUpdated:(NSNotification *)note {
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.bitrateLabel.text = [NSString stringWithFormat:@"%.02f kbps", [note.userInfo[@"broadcastThroughputBitrate"] floatValue]];
        
        //or you could just check against the self.gocoder
        self.bitrateLabel.text = [NSString stringWithFormat:@"%.02f kbps", [self.goCoder getCurrentBroadcastingNetworkBitrateThroughput]];
    });
}

- (void) orientationChanged:(NSNotification *)notification {
    
    /*
     We are looking at orientation changed events in order to demonstrate sending stream data to the server.
    */
    
    WOWZDataMap *params = [WOWZDataMap new];
    UIDevice * device = notification.object;
    switch(device.orientation) {
        case UIDeviceOrientationPortrait:
            [params setString:@"portrait" forKey:@"deviceOrientation"];
            [params setInteger:0 forKey:@"deviceRotation"];
            break;
            
        case UIDeviceOrientationPortraitUpsideDown:
            [params setString:@"portrait" forKey:@"deviceOrientation"];
            [params setInteger:180 forKey:@"deviceRotation"];
            break;
            
        case UIDeviceOrientationLandscapeLeft:
            [params setString:@"landscape" forKey:@"deviceOrientation"];
            [params setInteger:90 forKey:@"deviceRotation"];
            break;
            
        case UIDeviceOrientationLandscapeRight:
            [params setString:@"landscape" forKey:@"deviceOrientation"];
            [params setInteger:270 forKey:@"deviceRotation"];
            break;
            
        default:
            break;
    };
    
    if (params.data.count > 0) {
        [self.goCoder sendDataEvent:WOWZDataScopeStream eventName:@"onDeviceOrientation" params:params callback:nil];
    }
}


#pragma mark - Instance Methods

// Update the state of the UI controls
- (void) updateUIControls {
    if (self.goCoder.status.state != WOWZBroadcastStateIdle && self.goCoder.status.state != WOWZBroadcastStateBroadcasting) {
        // If a streaming broadcast session is in the process of starting up or shutting down,
        // disable the UI controls
        self.broadcastButton.enabled    = NO;
        self.torchButton.enabled        = NO;
        self.switchCameraButton.enabled = NO;
        self.settingsButton.enabled     = NO;
        self.closeButton.enabled        = NO;
        self.micButton.hidden           = YES;
        self.micButton.enabled          = NO;
        self.pingButton.hidden          = YES;
    } else {
        // Set the UI control state based on the streaming broadcast status, configuration,
        // and device capability
        self.broadcastButton.enabled    = YES;
        self.switchCameraButton.enabled = self.goCoderCameraPreview.cameras.count > 1;
        self.torchButton.enabled        = [self.goCoderCameraPreview.camera hasTorch];
        self.settingsButton.enabled     = !self.goCoder.isStreaming;
        self.closeButton.enabled        = !self.goCoder.isStreaming;
        // The mic icon should only be displayed while streaming and audio streaming has been enabled
        // in the GoCoder SDK configuration setiings
			[WowzaGoCoder requestPermissionForType:WowzaGoCoderPermissionTypeMicrophone response:^(WowzaGoCoderCapturePermission permission) {
				NSLog(@"Microphone permission is: %@", permission == WowzaGoCoderCapturePermissionAuthorized ? @"authorized" : @"denied");
				self.micButton.enabled          = self.goCoder.isStreaming && self.goCoder.config.audioEnabled && (permission == WowzaGoCoderCapturePermissionAuthorized);
				self.micButton.hidden           = !self.micButton.enabled;
			}];
			
        self.pingButton.hidden          = !self.goCoder.isStreaming;
        self.pingButton.enabled         = self.goCoder.isStreaming;
        
        self.bitmapOverlayImgView.hidden = !self.bitMapOverlayEffect;
        if(self.bitMapOverlayEffect){
            [_bitmapOverlayImgView setFrame:CGRectMake(0, 450, 140,140)];
            UIPanGestureRecognizer *panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleBitmapDragged:)];
            
            [_bitmapOverlayImgView addGestureRecognizer:panRecognizer];
            UIPinchGestureRecognizer *pinchRecognizer = [[UIPinchGestureRecognizer alloc]
                                                         initWithTarget:self action:@selector(handleBitmapOverlayPinch:)];
            pinchRecognizer.delegate = self;
            [self.bitmapOverlayImgView addGestureRecognizer:pinchRecognizer];
        }
    }
}
- (void)handleBitmapDragged:(UIPanGestureRecognizer *)recognizer {
    UIImageView *recView = (UIImageView *)recognizer.view;
    CGPoint translation = [recognizer translationInView:recView];
    
    recView.center = CGPointMake(recView.center.x + translation.x, recView.center.y + translation.y);
    [recognizer setTranslation:CGPointZero inView:recView];
    
    
    [_bitmapOverlayImgView setFrame: CGRectMake(recognizer.view.frame.origin.x,recognizer.view.frame.origin.y, recognizer.view.frame.size.width,recognizer.view.frame.size.height)];
}

- (void)handleBitmapOverlayPinch:(UIPinchGestureRecognizer *)recognizer
{
    UIGestureRecognizerState state = [recognizer state];
    
    if (state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateChanged)
    {
        CGFloat scale = [recognizer scale];
        
        [recognizer.view setTransform:CGAffineTransformScale(recognizer.view.transform, scale, scale)];
        [recognizer setScale:1.0];
    }
    if(state == UIGestureRecognizerStateEnded){
        [_bitmapOverlayImgView setFrame: CGRectMake(recognizer.view.frame.origin.x,recognizer.view.frame.origin.y, recognizer.view.frame.size.width,recognizer.view.frame.size.height)];
    }
}
#pragma mark - WOWZBroadcastStatusCallback Protocol Instance Methods

- (void) onWOWZStatus:(WOWZBroadcastStatus *) goCoderStatus {
    // A successful status transition has been reported by the GoCoder SDK
    
    switch (goCoderStatus.state) {

        case WOWZBroadcastStateIdle:
            self.timeLabel.hidden = YES;
            if (self.writeMP4 && self.mp4Writer.writing) {
                if (self.video_capture_queue) {
                    dispatch_async(self.video_capture_queue, ^{
                        [self.mp4Writer stopWriting];
                    });
                }
                else {
                    [self.mp4Writer stopWriting];
                }
            }
            self.writeMP4 = NO;
            break;
            
        case WOWZBroadcastStateReady:
            // A streaming broadcast session is starting up
            self.broadcastStartTime = kCMTimeInvalid;
            self.timeLabel.text = @"00:00";
            self.broadcastFrameCount = 0;
            break;
            
        case WOWZBroadcastStateBroadcasting:
            // A streaming broadcast session is running
            self.timeLabel.hidden = NO;
            self.writeMP4 = NO;
            if (self.recordVideoLocally) {
                self.mp4Writer = [MP4Writer new];
                self.writeMP4 = [self.mp4Writer prepareWithConfig:self.goCoderConfig];
                if (self.writeMP4) {
                    [self.mp4Writer startWriting];
                }
            }
            break;

        default:
            break;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.goCoder.status.state == WOWZBroadcastStateIdle || self.goCoder.status.state == WOWZBroadcastStateBroadcasting) {
            [self.broadcastButton setImage:[UIImage imageNamed:(self->_goCoder.status.state == WOWZBroadcastStateIdle) ? @"start_button" : @"stop_button"] forState:UIControlStateNormal];
        }
        
        [self updateUIControls];
    });
}

- (void) onWOWZEvent:(WOWZBroadcastStatus *) goCoderStatus {
    // If an event is reported by the GoCoder SDK, display an alert dialog describing the event,
    // but only if we haven't already shown an alert for this event
    
    dispatch_async(dispatch_get_main_queue(), ^{
        __block BOOL haveSeenAlertForEvent = NO;
        [self.receivedGoCoderEventCodes enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([((NSNumber *)obj) isEqualToNumber:[NSNumber numberWithInteger:goCoderStatus.error.code]]) {
                haveSeenAlertForEvent = YES;
                *stop = YES;
            }
        }];
                
        if (!haveSeenAlertForEvent) {
            [BroadcastViewController showAlertWithTitle:@"Live Streaming Event" status:goCoderStatus presenter:self];
            [self.receivedGoCoderEventCodes addObject:[NSNumber numberWithInteger:goCoderStatus.error.code]];
        }
        
        [self updateUIControls];
    });
}

- (void) onWOWZError:(WOWZBroadcastStatus *) goCoderStatus {
    // If an error is reported by the GoCoder SDK, display an alert dialog containing the error details
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [BroadcastViewController showAlertWithTitle:@"Live Streaming Error" status:goCoderStatus presenter:self];
        
        [self updateUIControls];
    });
}

#pragma mark - WOWZVideoSink

#warning Don't implement this protocol unless your application makes use of it
 
- (void) videoFrameWasCaptured:(nonnull CVImageBufferRef)imageBuffer framePresentationTime:(CMTime)framePresentationTime frameDuration:(CMTime)frameDuration {
    if (self.goCoder.isStreaming) {
        
        if (self.blackAndWhiteVideoEffect) {
            // convert frame to b/w using CoreImage tonal filter
            CIImage *frameImage = [[CIImage alloc] initWithCVImageBuffer:imageBuffer];
            CIFilter *grayFilter = [CIFilter filterWithName:@"CIPhotoEffectTonal"];
            [grayFilter setValue:frameImage forKeyPath:@"inputImage"];
            frameImage = [grayFilter outputImage];

            CIContext * context = [CIContext contextWithOptions:nil];
            [context render:frameImage toCVPixelBuffer:imageBuffer];
        }
        if(self.bitMapOverlayEffect){
            CIImage *wowzOverlayImg = _bitmapOverlayImgView.image.CIImage;
            
            CVPixelBufferLockBaseAddress( imageBuffer, 0 );
            CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(imageBuffer),
                                                         CVPixelBufferGetWidth(imageBuffer),
                                                         CVPixelBufferGetHeight(imageBuffer),
                                                         8,
                                                         CVPixelBufferGetBytesPerRow(imageBuffer),
                                                         CGColorSpaceCreateDeviceRGB(),
                                                         (CGBitmapInfo)
                                                         kCGBitmapByteOrder32Little |
                                                         kCGImageAlphaPremultipliedFirst);
            
            
            CGRect rect = _bitmapOverlayImgView.frame;
            CGFloat height = self.view.bounds.size.height;
            float maxHeight = height-150; /// accommodating for header / footer areas
            float y = maxHeight - ((rect.origin.y>maxHeight)?maxHeight:rect.origin.y);
            CGRect newFrame = CGRectMake(rect.origin.x, y, _bitmapOverlayImgView.frame.size.width, _bitmapOverlayImgView.frame.size.height);
            //            NSLog(@"Overlay data: %f = %f - %f", y,height, rect.origin.y);
            CGContextDrawImage(context, newFrame, [_bitmapOverlayImgView.image CGImage]);
            
            CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
            
            CIContext * contextOverlay = [CIContext contextWithOptions:nil];
            [contextOverlay render:wowzOverlayImg toCVPixelBuffer:imageBuffer];
        }
        
    }
}

- (void) videoCaptureInterruptionStarted {
    if (!self.goCoderConfig.backgroundBroadcastEnabled) {
        [self.goCoder endStreaming:self];
    }
}

- (void) videoCaptureUsingQueue:(nullable dispatch_queue_t)queue {
    self.video_capture_queue = queue;
}

#pragma mark - WOWZAudioSink

#warning Don't implement this protocol unless your application makes use of it
- (void) audioLevelDidChange:(float)level {
//    NSLog(@"%@ %0.2f", @"Audio level did change", level);
}

#warning Don't implement this protocol unless your application makes use of it
- (void) audioPCMFrameWasCaptured:(nonnull const AudioStreamBasicDescription *)pcmASBD bufferList:(nonnull const AudioBufferList *)bufferList time:(CMTime)time sampleRate:(Float64)sampleRate {
    // The commented-out code below simply dampens the amplitude of the audio data.
    // It is intended as an example of how one would access and modify the audio sample data.

//    int16_t *fdata = bufferList->mBuffers[0].mData;
//    
//    for (int i = 0; i < bufferList->mBuffers[0].mDataByteSize/sizeof(*fdata); i++) {
//        *fdata = (int16_t)(*fdata * 0.1);
//        fdata++;
//    }
}


#pragma mark - WOWZAudioEncoderSink

#warning Don't implement this protocol unless your application makes use of it
- (void) audioSampleWasEncoded:(nullable CMSampleBufferRef)data {
    if (self.writeMP4) {
        [self.mp4Writer appendAudioSample:data];
    }
}


#pragma mark - WOWZVideoEncoderSink

#warning Don't implement this protocol unless your application makes use of it
- (void) videoFrameWasEncoded:(nonnull CMSampleBufferRef)data {
    
    // update the broadcast time label
    if (CMTimeCompare(self.broadcastStartTime, kCMTimeInvalid) == 0) {
        self.broadcastStartTime = CMSampleBufferGetPresentationTimeStamp(data);
    }
    else {
        CMTime diff = CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(data), self.broadcastStartTime);
        Float64 seconds = CMTimeGetSeconds(diff);
        NSInteger duration = (NSInteger)seconds;
        
        NSString *timeString = [NSString stringWithFormat:@"%02ld:%02ld", (long)(duration / 60), (long)(duration % 60)];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.timeLabel.text = timeString;
        });
        
    }
    
    if (self.writeMP4) {
        [self.mp4Writer appendVideoSample:data];
    }
}

#pragma mark - WOWZDataSink

- (void) onData:(WOWZDataEvent *)dataEvent {
    NSLog(@"Got data - %@", dataEvent.description);
}

#pragma mark -

+ (void) showAlertWithTitle:(NSString *)title status:(WOWZBroadcastStatus *)status presenter:(UIViewController *)presenter {
    
    [SettingsViewController presentAlert:title message:status.description presenter:presenter];
}

+ (void) showAlertWithTitle:(NSString *)title error:(NSError *)error presenter:(UIViewController *)presenter {
    
    [SettingsViewController presentAlert:title message:error.localizedDescription presenter:presenter];
}


@end





