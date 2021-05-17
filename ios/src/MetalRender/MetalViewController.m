//
//  MetalSessionViewController.m
//  ZoomInstantSample
//
//  Created by Zoom Video Communications on 2019/5/27.
//  Copyright © 2019 Zoom. All rights reserved.
//

#import <ReplayKit/ReplayKit.h>
#import "MetalViewController.h"
#import "TopBarView.h"
#import "ControlBar.h"
#import "ChatInputView.h"
#import "BottomBarView.h"
#import "ChatView.h"
#import "KGModal.h"
#import "VideoZoomAppDelegate.h"
#import "SwitchBtn.h"

#define kBroadcastPickerTag 10001

@interface MetalRawdataRenderer () <ZoomInstantSDKRawDataPipeDelegate>

@end

@implementation MetalRawdataRenderer

- (void)onPixelBuffer:(CVPixelBufferRef)pixelBuffer rotation:(ZoomInstantSDKVideoRawDataRotation)rotation
{
    if (!pixelBuffer) {
        return;
    }

    if (self.isFullScreenDelegate) {
        [self updateStatisticInfo];
    }
    
    if (self.isFullScreenDelegate) {
        [self.metalView displayMetal:pixelBuffer rotation:rotation display:DisplayMode_LetterBox mirror:YES];
    } else {
        [self.metalView displayMetal:pixelBuffer rotation:rotation display:DisplayMode_PanAndScan mirror:YES];
    }
}

- (void)onRawDataStatusChanged:(ZoomInstantSDKUserRawdataStatus)userRawdataStatus {
    if (userRawdataStatus == ZoomInstantSDKUserRawdataOn) {
        [self.metalView removeAvatar];
    } else if (userRawdataStatus == ZoomInstantSDKUserRawdataOff) {
        [self.metalView addAvatar];
    }
}

- (void)updateStatisticInfo {
    NSString *statisticStr = @"";
    if (self.dataType == ZoomInstantSDKVideoType_VideoData) {
        ZoomInstantSDKVideoStatisticInfo *info = [self.user getVideoStatisticInfo];
        statisticStr = [NSString stringWithFormat:@"%@x%@ %@FPS", @(info.width), @(info.height), @(info.fps)];
    } else {
        ZoomInstantSDKShareStatisticInfo *info = [self.user getShareStatisticInfo];
        statisticStr = [NSString stringWithFormat:@"%@x%@ %@FPS", @(info.width), @(info.height), @(info.fps)];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (![statisticStr isEqualToString:@"0x0 0FPS"]) {
            self.statisticLabel.hidden = NO;
            self.statisticLabel.text = statisticStr;
        } else {
            self.statisticLabel.hidden = YES;
            self.statisticLabel.text = statisticStr;
        }
    });
}
@end

@interface MetalViewController () <ZoomInstantSDKDelegate, BottomBarViewDelegate, ChatInputViewDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate, UIScrollViewDelegate>
@property (strong, nonatomic) TopBarView              *topBarView;
@property (strong, nonatomic) ControlBar              *controlBarView;
@property (strong, nonatomic) ChatInputView           *chatInputView;
@property (strong, nonatomic) BottomBarView           *bottomView;
@property (strong, nonatomic) ChatView                *chatView;
@property (strong, nonatomic) SwitchBtn               *switchShareBtn;

@property (nonatomic, strong) UIView *shareView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *selectImgView;
@property (nonatomic, strong) UIButton *stopShareBtn;

@property (nonatomic, strong) NSMutableArray <MetalRawdataRenderer *>*rendererArr;

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, strong) NSTimer *speakerTimer;

@property (nonatomic, strong) UILabel *statisticLabel;

@property (nonatomic, assign) BOOL isReconnecting;
@end

@implementation MetalViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.rendererArr = [[NSMutableArray alloc] init];
    
    [ZoomInstantSDK shareInstance].delegate = self;
    
    [self initSubView];
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    MetalRawdataRenderer *fullRenderer = [self getFullViewRenderer];
    if (fullRenderer) {
        MetalView *view = fullRenderer.metalView;
        view.frame = self.view.bounds;
        [view setNeedsLayout];
    }
    
    [self.topBarView setNeedsLayout];
    [self.chatView setNeedsLayout];

    [self.controlBarView setNeedsLayout];
    if (_bottomView) {
        [self.bottomView setNeedsLayout];
    }
    
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation);
    if (landscape) {
        if (orientation == UIInterfaceOrientationLandscapeRight && IPHONE_X) {
            self.switchShareBtn.frame = CGRectMake(SAFE_ZOOM_INSETS+10, Top_Height + 5, 180, 35);
            
        } else {
            self.switchShareBtn.frame = CGRectMake(8, Top_Height + 5, 180, 35);
        }
        self.statisticLabel.frame = CGRectMake(SCREEN_WIDTH - CGRectGetWidth(_topBarView.leaveBtn.frame) - 90 - 30, 23.5, 90, 25);
    } else {
        self.switchShareBtn.frame = CGRectMake(8, (IPHONE_X ? Top_Height + SAFE_ZOOM_INSETS : Top_Height) + 5, 180, 35);
        self.statisticLabel.frame = CGRectMake(SCREEN_WIDTH - 90 - 16, (IPHONE_X ? Top_Height + SAFE_ZOOM_INSETS : Top_Height), 90, 25);
    }

    
    self.shareView.frame = self.view.bounds;
    self.scrollView.frame = self.view.bounds;
    self.selectImgView.frame = self.view.bounds;

    CGFloat bottom = IPHONE_X ? (landscape ? 21.f : 34.f) : 0.0;
    CGFloat right = IPHONE_X ? 44.0 : 0.0;
    CGFloat width = 104.0;
    CGFloat height = 28.0;
    self.stopShareBtn.frame = CGRectMake(SCREEN_WIDTH - width - 16 - right, SCREEN_HEIGHT - 16 - height - bottom, width, height);
}

- (BOOL)shouldAutorotate{
    return YES;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)sendAction:(NSString *)chatString
{
    NSLog(@"chatString===>%@",chatString);
    
    if (chatString.length == 0) {
        return;
    }
    
    [[[ZoomInstantSDK shareInstance] getChatHelper] SendChatToAll:chatString];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyBoardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyBoardDidShow:) name:UIKeyboardDidShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyBoardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyBoardDidHide:) name:UIKeyboardDidHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onDeviceOrientationChangeNotification:) name:UIDeviceOrientationDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    VideoZoomAppDelegate *delegate = (VideoZoomAppDelegate *)[UIApplication sharedApplication].delegate;
    delegate.canRotation = YES;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [[UIDevice currentDevice] setValue:@(UIInterfaceOrientationPortrait) forKey:@"orientation"];
    [UIViewController attemptRotationToDeviceOrientation];
    
    VideoZoomAppDelegate *delegate = (VideoZoomAppDelegate *)[UIApplication sharedApplication].delegate;
    delegate.canRotation = NO;
}

- (void)dealloc {
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [ZoomInstantSDK shareInstance].delegate = nil;
    [[KGModal sharedInstance] hideAnimated:NO];
}

- (void)showReconnectingUI
{
    MetalRawdataRenderer *fullRenderer = [self getFullViewRenderer];
    [self stopThumbViewVideo];
    [self.rendererArr removeAllObjects];
    [self.bottomView removeAllThumberViewItem];
    
    ZoomInstantSDKSession *session = [[ZoomInstantSDK shareInstance] getSession];
    if (session) {
        ZoomInstantSDKUser *user = [session getMySelf];
        [user.getVideoPipe subscribeWithDelegate:fullRenderer resolution:ZoomInstantSDKVideoResolution_720];
        fullRenderer.dataType = ZoomInstantSDKVideoType_VideoData;
        fullRenderer.user = user;
        [self.rendererArr addObject:fullRenderer];
    }
    
    [UIView animateWithDuration:0.3 animations:^{
        [self.chatInputView removeFromSuperview];
        [self.chatView removeFromSuperview];
        [self.controlBarView removeFromSuperview];
        self.statisticLabel.alpha = 0.0;
    }];
    
    [self updateTitleIsJoined:NO];
}

- (void)initSubView {
    
    [self initfullScreenRender];
    
    __weak MetalViewController *weakSelf = self;
    [self updateTitleIsJoined:NO];
    
    self.topBarView.endOnClickBlock = ^(void) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Are you sure that you want to leave the session?"
                                                                                 message:nil
                                                                          preferredStyle:UIAlertControllerStyleActionSheet];
        
        [alertController addAction:[UIAlertAction actionWithTitle:@"Leave"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *action) {
                                                              [[ZoomInstantSDK shareInstance] leaveSession:NO];
                                                              [self dismissViewControllerAnimated:YES completion:nil];
                                                          }]];
        
        if ([[[[ZoomInstantSDK shareInstance] getSession] getMySelf] isHost]) {
            [alertController addAction:[UIAlertAction actionWithTitle:@"End Session"
                                                                style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction *action) {
                                                                  [[ZoomInstantSDK shareInstance] leaveSession:YES];
                                                              }]];
        }
        
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        }]];
        
        UIPopoverPresentationController *popover = alertController.popoverPresentationController;
        if (popover)
        {
            UIButton *btn = weakSelf.topBarView.leaveBtn;
            popover.sourceView = btn;
            popover.sourceRect = btn.bounds;
            popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
        }
        VideoZoomAppDelegate *appDelegate = (VideoZoomAppDelegate *)[UIApplication sharedApplication].delegate;
        [[appDelegate topViewController] presentViewController:alertController animated:YES completion:nil];
    };
    self.topBarView.sessionInfoOnClickBlock = ^(void) {
        [weakSelf showSessionInfo];
    };
    
    [self.view addSubview:self.switchShareBtn];
    [self.view addSubview:self.bottomView];
    [self.view addSubview:self.chatView];
    [self.view addSubview:self.statisticLabel];
    
    self.chatInputView.hidden = YES;
}

- (void)initfullScreenRender {
    MetalView *view = [[MetalView alloc] initWithFrame:self.view.bounds];
    MetalRawdataRenderer *renderer = [[MetalRawdataRenderer alloc] init];
    renderer.isFullScreenDelegate = YES;
    renderer.dataType = ZoomInstantSDKVideoType_VideoData;
    renderer.metalView = view;
    renderer.statisticLabel = self.statisticLabel;
    
    [self.view addSubview:view];
    view.userInteractionEnabled = YES;
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onSingleTap)];
    [view addGestureRecognizer:tapGesture];
    
    ZoomInstantSDKUser *user = [[[ZoomInstantSDK shareInstance] getSession] getMySelf];
    [user.getVideoPipe subscribeWithDelegate:renderer resolution:ZoomInstantSDKVideoResolution_720];
    
    renderer.user = user;
    [self.rendererArr addObject:renderer];
}

- (void)onSingleTap {
    
    if ([self.chatInputView.chatTextField isEditing]) {
        [self.chatInputView hideKeyBoard];
        return;
    }
    
    if (self.chatView.hidden == NO) {
        [UIView animateWithDuration:0.3 animations:^{
            self.chatView.hidden = YES;
            self.controlBarView.hidden = YES;
            self.statisticLabel.alpha = 0.0;
        }];
    } else {
        [UIView animateWithDuration:0.3 animations:^{
            self.chatView.hidden = NO;
            self.controlBarView.hidden = NO;
            self.statisticLabel.alpha = 1.0;
        }];
    }
}

- (void)leave
{
    MetalRawdataRenderer *fullRenderer = [self getFullViewRenderer];
    if (fullRenderer) {
        if (fullRenderer.dataType == ZoomInstantSDKVideoType_ShareData) {
            [fullRenderer.user.getSharePipe unSubscribeWithDelegate:fullRenderer];
        } else {
            [fullRenderer.user.getVideoPipe unSubscribeWithDelegate:fullRenderer];
        }
        [self.rendererArr removeObject:fullRenderer];
    }
    
    [self stopThumbViewVideo];
    [self.bottomView removeAllThumberViewItem];
    [self.rendererArr removeAllObjects];
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)noVideofailBack {
    ZoomInstantSDKUser *user = [[[ZoomInstantSDK shareInstance] getSession] getMySelf];
    MetalRawdataRenderer *fullRenderer = [self getFullViewRenderer];
    if (fullRenderer) {
        [user.getVideoPipe unSubscribeWithDelegate:fullRenderer];
        fullRenderer.user = user;
        fullRenderer.dataType = ZoomInstantSDKVideoType_VideoData;
    } else {
        MetalView *view = [[MetalView alloc] initWithFrame:self.view.bounds];
        MetalRawdataRenderer *renderer = [[MetalRawdataRenderer alloc] init];
        renderer.isFullScreenDelegate = YES;
        renderer.metalView = view;
        renderer.user = user;
        renderer.statisticLabel = self.statisticLabel;
        
        if (user.shareStatus.sharingStatus == ZoomInstantSDKReceiveSharingStatus_Start) {
            renderer.dataType = ZoomInstantSDKVideoType_ShareData;
            [user.getVideoPipe subscribeWithDelegate:renderer resolution:ZoomInstantSDKVideoResolution_720];
        } else {
            renderer.dataType = ZoomInstantSDKVideoType_VideoData;
            [user.getVideoPipe subscribeWithDelegate:renderer resolution:ZoomInstantSDKVideoResolution_720];
        }
    }
}

- (void)addThumberViewWithArr:(NSArray *)userArray helper:(ZoomInstantSDKUserHelper *)helper {
    
    NSUInteger canSubNum = userArray.count;
    if (userArray.count > 3) {
        canSubNum = 3;
    }
    for (int i = 0; i < userArray.count; i++) {
        ZoomInstantSDKUser *user = userArray[i];
        MetalRawdataRenderer *thumbRenderer = [self getThumbRendererForUser:user];
        if (thumbRenderer) {
            continue;
        }
        
        MetalView *view = [[MetalView alloc] initWithFrame:CGRectZero];
        thumbRenderer = [[MetalRawdataRenderer alloc] init];
        thumbRenderer.isFullScreenDelegate = NO;
        thumbRenderer.metalView = view;
        thumbRenderer.user = user;
        thumbRenderer.dataType = ZoomInstantSDKVideoType_VideoData;
        [self.rendererArr addObject:thumbRenderer];

        if (i < canSubNum) {
            [user.getVideoPipe subscribeWithDelegate:thumbRenderer resolution:ZoomInstantSDKVideoResolution_90];
        }
        
        ViewItem *item = [[ViewItem alloc] init];
        item.userId = user.getUserId;
        item.view = view;
        item.isActive = NO;
        item.itemName = user.getUserName;

        [self.bottomView addThumberViewItem:item];
        
        if (!helper) {
            [self viewItemSelected:item];
        }
    }

    [self.view insertSubview:self.controlBarView aboveSubview:self.bottomView];
}

- (void)showSessionInfo {
    NSLog(@"showSessionInfo");
    [[KGModal sharedInstance] setModalBackgroundColor:[UIColor whiteColor]];
    [[KGModal sharedInstance] setCloseButtonType:KGModalCloseButtonTypeNone];
    [[KGModal sharedInstance] setTapOutsideToDismiss:YES];
    [[KGModal sharedInstance] showWithContentView:[self alertViewOfSessionInfo] andAnimated:YES];
}

- (UIView*)alertViewOfSessionInfo {
    UIView *dialogView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 280, 237)];
    dialogView.layer.masksToBounds = YES;
    
    NSArray *userArr = [[[ZoomInstantSDK shareInstance] getSession] getAllUsers];
    ZoomInstantSDKSession *session = [[ZoomInstantSDK shareInstance] getSession];
    
    //Title Label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 21, 256, 24)];
    titleLabel.text = NSLocalizedString(@"Session Information", @"");
    titleLabel.textColor = RGBCOLOR(0x23, 0x23, 0x23);
    titleLabel.textAlignment = NSTextAlignmentLeft;
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [dialogView addSubview:titleLabel];
    
    UILabel *sessionNameTitle = [[UILabel alloc] initWithFrame:CGRectMake(24, CGRectGetMaxY(titleLabel.frame) + 25, 256, 20)];
    sessionNameTitle.text = NSLocalizedString(@"Session name", @"");
    sessionNameTitle.textColor = RGBCOLOR(0x74, 0x74, 0x87);
    sessionNameTitle.textAlignment = NSTextAlignmentLeft;
    sessionNameTitle.font = [UIFont systemFontOfSize:12.0];
    [dialogView addSubview:sessionNameTitle];
    
    UILabel *sessionNameValue = [[UILabel alloc] initWithFrame:CGRectMake(24, CGRectGetMaxY(sessionNameTitle.frame), 256, 16)];
    sessionNameValue.text = session.getSessionName;
    sessionNameValue.textColor = RGBCOLOR(0x23, 0x23, 0x23);
    sessionNameValue.textAlignment = NSTextAlignmentLeft;
    sessionNameValue.font = [UIFont boldSystemFontOfSize:16.0];
    [dialogView addSubview:sessionNameValue];
    
    UILabel *pswTitle = [[UILabel alloc] initWithFrame:CGRectMake(24, CGRectGetMaxY(sessionNameValue.frame) + 20, 256, 20)];
    pswTitle.text = NSLocalizedString(@"Password", @"");
    pswTitle.textColor = RGBCOLOR(0x74, 0x74, 0x87);
    pswTitle.textAlignment = NSTextAlignmentLeft;
    pswTitle.font = [UIFont systemFontOfSize:12.0];
    [dialogView addSubview:pswTitle];
    
    BOOL hasPassword = (session.getSessionPassword && ![session.getSessionPassword isEqualToString:@""]);
    UILabel *pswValue = [[UILabel alloc] initWithFrame:CGRectMake(24, CGRectGetMaxY(pswTitle.frame), 256, 16)];
    pswValue.text = hasPassword ? session.getSessionPassword : @"Not Set";
    pswValue.textColor = hasPassword ? RGBCOLOR(0x23, 0x23, 0x23) : RGBCOLOR(0x74, 0x74, 0x87);
    pswValue.textAlignment = NSTextAlignmentLeft;
    pswValue.font = [UIFont boldSystemFontOfSize:16.0];
    [dialogView addSubview:pswValue];
    
    UILabel *participantsTitle = [[UILabel alloc] initWithFrame:CGRectMake(24, CGRectGetMaxY(pswValue.frame) + 20, 256, 20)];
    participantsTitle.text = NSLocalizedString(@"Participants", @"");
    participantsTitle.textColor = RGBCOLOR(0x74, 0x74, 0x87);
    participantsTitle.textAlignment = NSTextAlignmentLeft;
    participantsTitle.font = [UIFont systemFontOfSize:12.0];
    [dialogView addSubview:participantsTitle];
    
    NSUInteger count = userArr.count;
    if (count == 0) {
        count = 1;
    }
    UILabel *pValue = [[UILabel alloc] initWithFrame:CGRectMake(24, CGRectGetMaxY(participantsTitle.frame), 256, 16)];
    pValue.text = [NSString stringWithFormat:@"%@", @(count)];
    pValue.textColor = RGBCOLOR(0x23, 0x23, 0x23);
    pValue.textAlignment = NSTextAlignmentLeft;
    pValue.font = [UIFont boldSystemFontOfSize:16.0];
    [dialogView addSubview:pValue];
    
    return dialogView;
}

- (void)showShareOptionView {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Share" message:nil preferredStyle: UIAlertControllerStyleActionSheet];
    if (@available(iOS 11.0, *)) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Share Device Screen"
                                                  style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                                      BOOL isOtherSharing = [[[ZoomInstantSDK shareInstance] getShareHelper] isOtherSharing];
                                                      if (isOtherSharing) {
                                                          MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
                                                          hud.mode = MBProgressHUDModeText;
                                                          hud.label.text = @"Others are sharing";
                                                          // Move to bottm center.
                                                          hud.offset = CGPointMake(0.f, MBProgressMaxOffset);
                                                          [hud hideAnimated:YES afterDelay:2.f];
                                                          return;
                                                      }
                                                      
                                                      if (@available(iOS 12.0, *)) {
                                                          RPSystemBroadcastPickerView *broadcastView = [[RPSystemBroadcastPickerView alloc] init];
                                                          broadcastView.preferredExtension = kScreenShareBundleId;
                                                          broadcastView.tag = kBroadcastPickerTag;

                                                          [self.view addSubview:broadcastView];
                                                          
                                                          [self sendTouchDownEventToBroadcastButton];

                                                      } else {
                                                          // Guide page
                                                      }
                                                  }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Share a Picture"
                                              style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                                  [UIView animateWithDuration: 0. delay: 0 options: UIViewAnimationOptionLayoutSubviews  animations:^{

                                                  } completion:^(BOOL finished){
                                                      BOOL isOtherSharing = [[[ZoomInstantSDK shareInstance] getShareHelper] isOtherSharing];
                                                      if (isOtherSharing) {
                                                          MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
                                                          hud.mode = MBProgressHUDModeText;
                                                          hud.label.text = @"Others are sharing";
                                                          // Move to bottm center.
                                                          hud.offset = CGPointMake(0.f, MBProgressMaxOffset);
                                                          [hud hideAnimated:YES afterDelay:2.f];
                                                          return;
                                                      }
                                                      
                                                      UIImagePickerController *controller = [[UIImagePickerController alloc] init];
                                                      controller.delegate = self;
                                                      controller.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
                                                      [self presentViewController:controller animated:YES completion:NULL];
                                                  } ];
                                              }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover)
    {
        UIButton *btn = (UIButton*)self.controlBarView.shareBtn;
        popover.sourceView = btn;
        popover.sourceRect = btn.bounds;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)sendTouchDownEventToBroadcastButton
{
    if (@available(iOS 12.0, *)) {
        RPSystemBroadcastPickerView *broadcastView = [self.view viewWithTag:kBroadcastPickerTag];
        if (!broadcastView) return;

        
        for (UIView *subView in broadcastView.subviews) {
            if ([subView isKindOfClass:[UIButton class]])
            {
                UIButton *broadcastBtn = (UIButton *)subView;
                [broadcastBtn sendActionsForControlEvents:UIControlEventAllTouchEvents];
                break;
            }
        }
    }
}

#pragma mark - for view tool -
- (void)updateTitleIsJoined:(BOOL)isJoined
{
    BOOL beforeSession = NO;
    ZoomInstantSDKSession *session = [[ZoomInstantSDK shareInstance] getSession];
    if (!session) {
        beforeSession = YES;
    }
    
    if (beforeSession) {
        [self.topBarView updateTopBarWithSessionName:session.getSessionName totalNum:1 password:session.getSessionPassword isJoined:isJoined];
    } else {
        NSArray *allUsers = [session getAllUsers];
        [self.topBarView updateTopBarWithSessionName:session.getSessionName totalNum:allUsers.count password:session.getSessionPassword isJoined:isJoined];
    }
}

- (MetalRawdataRenderer *)getFullViewRenderer
{
    for (MetalRawdataRenderer *renderer in self.rendererArr) {
        if (renderer.isFullScreenDelegate) {
            return renderer;
        }
    }
    return nil;
}

- (MetalRawdataRenderer *)getThumbRendererForUser:(ZoomInstantSDKUser *)user
{
    for (MetalRawdataRenderer *renderer in self.rendererArr) {
        if (!renderer.isFullScreenDelegate && renderer.user == user) {
            return renderer;
        }
    }
    return nil;
}

- (void)removeThumbRendererForUser:(ZoomInstantSDKUser *)user
{
    MetalRawdataRenderer *removeRenderer = nil;
    for (MetalRawdataRenderer *renderer in self.rendererArr) {
        if (!renderer.isFullScreenDelegate && renderer.user == user) {
            removeRenderer = renderer;
        }
    }

    if (removeRenderer) [self.rendererArr removeObject:removeRenderer];
}

#pragma mark - singleton -
- (TopBarView *)topBarView {
    if (!_topBarView) {
        _topBarView = [[TopBarView alloc] init];
        [self.view addSubview:self.topBarView];
    }
    return _topBarView;
}

- (ChatInputView *)chatInputView {
    if (!_chatInputView) {
        _chatInputView = [[ChatInputView alloc] initWithView:self.view];
        _chatInputView.delegate = self;
    }
    
    return _chatInputView;
}


- (ChatView *)chatView {
    if (!_chatView) {
        _chatView = [[ChatView alloc] init];
        _chatView.userInteractionEnabled = YES;
        UITapGestureRecognizer * tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onSingleTap)];
        [_chatView addGestureRecognizer:tapGesture];
    }
    
    return _chatView;
}

- (BottomBarView *)bottomView {
    if (!_bottomView) {
        _bottomView = [[BottomBarView alloc] initWithDelegate:self];
        _bottomView.frame = CGRectMake(0, SCREEN_HEIGHT - kTableHeight, SCREEN_WIDTH, kTableHeight);
        [self.view addSubview:_bottomView];
    }
    
    return _bottomView;
}

- (ControlBar *)controlBarView {
    if (!_controlBarView) {
        _controlBarView = [[ControlBar alloc] init];
        __weak MetalViewController *weakSelf = self;
        _controlBarView.chatOnClickBlock = ^(void) {
            [weakSelf.chatInputView showKeyBoard];
        };
        _controlBarView.shareOnClickBlock = ^(void) {
            [weakSelf showShareOptionView];
        };
    }
    return _controlBarView;
}

- (SwitchBtn *)switchShareBtn {
    if (!_switchShareBtn) {
        _switchShareBtn = [[SwitchBtn alloc] initWithFrame:CGRectZero];
        [_switchShareBtn setTitle:@"Switch to Share" forState:UIControlStateNormal];
        _switchShareBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [_switchShareBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _switchShareBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        _switchShareBtn.clipsToBounds = YES;
        _switchShareBtn.layer.cornerRadius = 6;
        [_switchShareBtn addTarget:self action:@selector(switchToShare:) forControlEvents:UIControlEventTouchUpInside];
        _switchShareBtn.hidden = YES;
    }
    
    return _switchShareBtn;
}

- (UILabel *)statisticLabel {
    if (!_statisticLabel) {
        _statisticLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _statisticLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        _statisticLabel.font = [UIFont systemFontOfSize:9.0];
        _statisticLabel.textColor = [UIColor whiteColor];
        _statisticLabel.numberOfLines = 1;
        _statisticLabel.textAlignment = 1;
        _statisticLabel.clipsToBounds = YES;
        _statisticLabel.layer.cornerRadius = 6.0;
        _statisticLabel.hidden = YES;
    }
    return _statisticLabel;
}

#pragma mark - uiimagepicker delegate -
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    
    self.shareView = [[UIView alloc] initWithFrame:self.view.bounds];
    UIImage *selectPic = info[UIImagePickerControllerOriginalImage];
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.backgroundColor = [UIColor blackColor];
    self.scrollView.delegate = self;
    self.scrollView.bounces = NO;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 3.0;
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleShareTap:)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.numberOfTouchesRequired = 1;
    [self.scrollView addGestureRecognizer:doubleTap];
    
    self.selectImgView = [[UIImageView alloc] initWithImage:selectPic];
    self.selectImgView.contentMode = UIViewContentModeScaleAspectFit;
    self.selectImgView.frame = self.view.bounds;
    
    [self.scrollView addSubview:self.selectImgView];
    [self.shareView addSubview:self.scrollView];
    [self.view addSubview:self.shareView];
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation);
    CGFloat bottom = IPHONE_X ? (landscape ? 21.f : 34.f) : 0.0;
    CGFloat right = IPHONE_X ? 44.0 : 0.0;
    CGFloat width = 104.0;
    CGFloat height = 28.0;
    
    self.stopShareBtn = [[UIButton alloc] initWithFrame:CGRectMake(SCREEN_WIDTH - width - 16 - right, SCREEN_HEIGHT - 16 - height - bottom, width, height)];
    [self.stopShareBtn setTitle:@"STOP SHARE" forState:UIControlStateNormal];
    self.stopShareBtn.clipsToBounds = YES;
    self.stopShareBtn.layer.cornerRadius = height * 0.5;
    self.stopShareBtn.titleLabel.font = [UIFont systemFontOfSize:12.0];
    self.stopShareBtn.backgroundColor = [UIColor redColor];
    [self.stopShareBtn addTarget:self action:@selector(stopShareBtnClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.stopShareBtn];
    
    [[[ZoomInstantSDK shareInstance] getShareHelper] startShareWithView:self.shareView];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark - for share -
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.selectImgView;
}

- (void)handleDoubleShareTap:(UIGestureRecognizer *)gestureRecognizer
{
    CGFloat zs = self.scrollView.zoomScale;
    zs = (zs == self.scrollView.minimumZoomScale) ? self.scrollView.maximumZoomScale : self.scrollView.minimumZoomScale;
    CGRect zoomRect = [self zoomRectForScale: zs withCenter: [gestureRecognizer locationInView: gestureRecognizer.view]];
    [self.scrollView zoomToRect: zoomRect animated: YES];
}

- (CGRect)zoomRectForScale:(float)scale withCenter:(CGPoint)center
{
    CGRect zoomRect;
    
    CGFloat w = [self.scrollView frame].size.width;
    CGFloat h = [self.scrollView frame].size.height;
    zoomRect.size.height = h / scale;
    zoomRect.size.width  = w / scale;
    
    CGFloat x = center.x - (zoomRect.size.width  / 2.0);
    CGFloat y = center.y - (zoomRect.size.height / 2.0);
    
    CGSize shareSource = self.view.bounds.size;
    CGFloat offsetX = fabs(shareSource.width / scale - w) / 2;
    CGFloat offsetY = fabs(shareSource.height / scale - h) / 2;
    if (x < offsetX) x = 0;
    if (y < offsetY) y = 0;
    if (x > offsetX && (x + zoomRect.size.width) * scale > shareSource.width) x = (shareSource.width - w) / scale;
    if (y > offsetY && (y + zoomRect.size.height) * scale > shareSource.height) y = (shareSource.height - h) / scale;
    zoomRect.origin.x = x;
    zoomRect.origin.y = y;
    
    return zoomRect;
}

- (void)stopShareBtnClicked:(id)sender {
    NSLog(@"stop share");
    [self.shareView removeFromSuperview];
    [self.stopShareBtn removeFromSuperview];
    [[[ZoomInstantSDK shareInstance] getShareHelper] stopShare];
    
    [self pinMyself];
}


#pragma mark - ZoomInstantSDK delegate -
- (void)onError:(ZoomInstantSDKERROR)ErrorType detail:(NSInteger)details
{
    NSLog(@"ErrorType========%@, %@",@(ErrorType), [self formatErrorString:ErrorType]);
    NSLog(@"ErrorDetails========%@",@(details));
    
    switch (ErrorType) {
        case Errors_Session_Join_Failed:
        {
            [self leave];
        }
            break;
        case Errors_Session_Disconncting:
        {
        }
            break;
        case Errors_Session_Reconncting:
        {
            [self showReconnectingUI];
            self.isReconnecting = YES;
        }
            break;
        default:
            break;
    }
    
    NSString *string = [self formatErrorString:ErrorType];
    if (string) {
        string = [string stringByAppendingFormat:@". Error code: %@", @(details)];
        UIWindow *window = [[UIApplication sharedApplication].windows lastObject];
        MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:window animated:YES];
        hud.mode = MBProgressHUDModeText;
        hud.label.text = string;
        hud.offset = CGPointMake(0.f, MBProgressMaxOffset);
        [hud hideAnimated:YES afterDelay:4.f];
    }
}

- (void)onSessionJoin {
    NSLog(@"onSessionJoin====>");
    [self.view addSubview:self.controlBarView];
    [self.view addSubview:self.chatInputView];
    self.chatInputView.hidden = NO;
    [self.view addSubview:self.chatView];
    
    [self updateTitleIsJoined:YES];
    
    if (self.isReconnecting) {
        MetalRawdataRenderer *fullRenderer = [self getFullViewRenderer];
        [fullRenderer.user.getVideoPipe subscribeWithDelegate:fullRenderer resolution:ZoomInstantSDKVideoResolution_720];
        self.isReconnecting = NO;
    }
    
    ZoomInstantSDKUser *mySelf = [[[ZoomInstantSDK shareInstance] getSession] getMySelf];
    if (mySelf) {
        [self onUserJoin:nil users:@[mySelf]];
    }
}

- (void)onSessionLeave {
    NSLog(@"onSessionLeave====>");

    [self leave];
}

- (void)onUserJoin:(ZoomInstantSDKUserHelper *)helper users:(NSArray<ZoomInstantSDKUser *> *)userArray {
    NSLog(@"onUserJoin====>");
    
    NSArray *allUsers = [[[ZoomInstantSDK shareInstance] getSession] getAllUsers];
    [self addThumberViewWithArr:allUsers helper:helper];
    
    [self updateTitleIsJoined:YES];
}

- (void)onUserLeave:(ZoomInstantSDKUserHelper *)helper users:(NSArray<ZoomInstantSDKUser *> *)userArray {
    MetalRawdataRenderer *fullRenderer = [self getFullViewRenderer];
    for (int i = 0; i < userArray.count; i++) {
        ZoomInstantSDKUser *user = userArray[i];

        MetalRawdataRenderer *renderer = [self getThumbRendererForUser:user];
        if (renderer) {
            [user.getVideoPipe unSubscribeWithDelegate:renderer];
            [self removeThumbRendererForUser:user];
        }

        [self.bottomView removeThumberViewItemWithUserId:user.getUserId];
        
        if ([user isEqual:fullRenderer.user]) {
            [self pinMyself];
        }
    }
    
    [self updateTitleIsJoined:YES];
}

- (void)onUserVideoStatusChanged:(ZoomInstantSDKVideoHelper *)helper user:(NSArray<ZoomInstantSDKUser *> *)userArray{
    NSLog(@"onUserVideoStatusChanged====>: %@", userArray);
    NSArray *allUsers = [[[ZoomInstantSDK shareInstance] getSession] getAllUsers];
    NSLog(@"ok haha");
    for (int i = 0; i<allUsers.count; i++) {
        ZoomInstantSDKUser *user = allUsers[i];
        NSLog(@"Ok haha %@", [user getUserName]);
    }
}

- (void)onUserShareStatusChanged:(ZoomInstantSDKShareHelper *)helper user:(ZoomInstantSDKUser *)user status:(ZoomInstantSDKReceiveSharingStatus)status
{
    NSLog(@"onUserShareStatusChanged====>%@, %@", user.getUserId, @(status));
    ZoomInstantSDKUser *myUser = [[[ZoomInstantSDK shareInstance] getSession] getMySelf];
    if (user == myUser) {
        return;
    }
    MetalRawdataRenderer *fullRenderer = [self getFullViewRenderer];
    [fullRenderer.metalView removeAvatar];
    
    if (status == ZoomInstantSDKReceiveSharingStatus_Stop ||
        status == ZoomInstantSDKReceiveSharingStatus_None) {
        [fullRenderer.metalView removeAvatar];
        
        if (!user.videoStatus.on && (user.shareStatus.sharingStatus != ZoomInstantSDKReceiveSharingStatus_Start)) {
            [fullRenderer.metalView addAvatar];
        }
    }
    
    fullRenderer.user = user;
    MetalRawdataRenderer *thumbRenderer = [self getThumbRendererForUser:user];
    if (thumbRenderer) {
        [user.getVideoPipe subscribeWithDelegate:thumbRenderer resolution:ZoomInstantSDKVideoResolution_90];
    }
    if (status == ZoomInstantSDKReceiveSharingStatus_Start) {
        self.switchShareBtn.sharedUser = user;
        
        fullRenderer.dataType = ZoomInstantSDKVideoType_ShareData;
        [user.getSharePipe subscribeWithDelegate:fullRenderer resolution:ZoomInstantSDKVideoResolution_720];
        
        NSArray *viewItems = [self.bottomView getThumberViewItems:user.getUserId];
        ViewItem *item = [viewItems firstObject];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self stopThumbViewVideo];
            [self.bottomView scrollToVisibleArea:item];
        });
    } else if (status == ZoomInstantSDKReceiveSharingStatus_Stop) {
        self.switchShareBtn.sharedUser = nil;
        fullRenderer.dataType = ZoomInstantSDKVideoType_VideoData;
        [user.getVideoPipe subscribeWithDelegate:fullRenderer resolution:ZoomInstantSDKVideoResolution_720];
    }
    
    for (ViewItem *item in self.bottomView.viewArray) {
        if ([user.getUserId isEqualToString:item.userId]) {
            [self viewItemSelected:item];
        }
    }
    self.switchShareBtn.hidden = YES;
}

- (void)onUserActiveAudioChanged:(ZoomInstantSDKUserHelper *)helper users:(NSArray<ZoomInstantSDKUser *> *)userArray{
    for (ZoomInstantSDKUser *user in userArray) {
        [self.bottomView activeThumberViewItem:user.getUserId];
    }

    [self startSpeakerTimer];
}

- (void)onUserAudioStatusChanged:(ZoomInstantSDKAudioHelper *)helper user:(NSArray<ZoomInstantSDKUser *> *)userArray {
// can update audio UI here
    ZoomInstantSDKUser *myUser = [[[ZoomInstantSDK shareInstance] getSession] getMySelf];
    for (ZoomInstantSDKUser *user in userArray) {
        if ([user isEqual:myUser]) {
            if (user.audioStatus.audioType == ZoomInstantSDKAudioType_None) {
                [self.controlBarView.audioBtn setImage:[UIImage imageNamed:@"icon_no_audio"] forState:UIControlStateNormal];
            } else {
                if (!user.audioStatus.isMuted) {
                    [self.controlBarView.audioBtn setImage:[UIImage imageNamed:@"icon_mute"] forState:UIControlStateNormal];
                } else {
                    [self.controlBarView.audioBtn setImage:[UIImage imageNamed:@"icon_unmute"] forState:UIControlStateNormal];
                }
            }
        }
    }
}

- (void)onChatNewMessageNotify:(ZoomInstantSDKChatHelper *)helper message:(ZoomInstantSDKChatMessage *)msg{
    [self.chatView.chatMsgArray addObject:msg];
    [self.chatView.tableView reloadData];
    [self.chatView scrollToBottom];
}

- (void)onSessionNeedPassword:(ZoomInstantSDKERROR (^)(NSString *password, BOOL leaveSessionIgnorePassword))completion
{
    if (completion) {
        self.joinSessionOrIgnorePasswordBlock = completion;
        
        [self showZoomPasswordAlert:NO];
    }
}

- (void)onSessionPasswordWrong:(ZoomInstantSDKERROR (^)(NSString *password, BOOL leaveSessionIgnorePassword))completion
{
    if (completion) {
        self.joinSessionOrIgnorePasswordBlock = completion;
        
        [self showZoomPasswordAlert:YES];
    }
}

- (void)showZoomPasswordAlert:(BOOL)wrongPwd
{
    NSString *message = wrongPwd ? NSLocalizedString(@"Incorrect password, please try again", @"") : NSLocalizedString(@"Please enter your password", @"");
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:message delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Join", nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    [[alert textFieldAtIndex:0] becomeFirstResponder];
    
    [alert show];
}

#pragma mark - audio rawdata delegate -
- (void)onMixedAudioRawDataReceived:(ZoomInstantSDKAudioRawData *)rawData
{

}

- (void)onOneWayAudioRawDataReceived:(ZoomInstantSDKAudioRawData *)rawData user:(ZoomInstantSDKUser *)user
{

}

#pragma mark - BottomBarViewDelegate -
- (void)stopThumbViewVideo {
    for (MetalRawdataRenderer *renderer in self.rendererArr) {
        if (renderer.isFullScreenDelegate) {
            continue;
        }
        if (renderer.dataType == ZoomInstantSDKVideoType_ShareData) {
            [renderer.user.getSharePipe unSubscribeWithDelegate:renderer];
        } else {
            [renderer.user.getVideoPipe unSubscribeWithDelegate:renderer];
        }
    }
}

- (void)startThumbViewVideo {
    NSArray <UITableViewCell *> *cellArray = self.bottomView.thumbTableView.visibleCells;
    for (int i = 0; i < cellArray.count; i++) {
        UITableViewCell *cell = [cellArray objectAtIndex:i];
        NSIndexPath *indexPath = [self.bottomView.thumbTableView indexPathForCell:cell];
        
        ViewItem *item = [self.bottomView.viewArray objectAtIndex:indexPath.row];
        
        for (MetalRawdataRenderer *renderer in self.rendererArr) {
            if (renderer.isFullScreenDelegate) {
                continue;
            }
            if ([renderer.user.getUserId isEqualToString:item.userId]) {
                [renderer.user.getVideoPipe subscribeWithDelegate:renderer resolution:ZoomInstantSDKVideoResolution_90];
            }
        }
    }
}

- (void)pinThumberViewItem:(ViewItem *)item {
    
    if (!item) {
        return;
    }
    [self viewItemSelected:item];
    
    ZoomInstantSDKUser *user = [[[ZoomInstantSDK shareInstance] getSession] getUser:item.userId];
    MetalRawdataRenderer *fullRenderer = [self getFullViewRenderer];
    
    if (fullRenderer.dataType == ZoomInstantSDKVideoType_ShareData) {
        [fullRenderer.user.getSharePipe unSubscribeWithDelegate:fullRenderer];
    } else {
        [fullRenderer.user.getVideoPipe unSubscribeWithDelegate:fullRenderer];
    }
    
    if (user && fullRenderer) {
        fullRenderer.user = user;
        fullRenderer.dataType = ZoomInstantSDKVideoType_VideoData;
        [user.getVideoPipe subscribeWithDelegate:fullRenderer resolution:ZoomInstantSDKVideoResolution_720];
    }
        
    [self updateTitleIsJoined:YES];
    
    if (self.switchShareBtn.sharedUser) {
        self.switchShareBtn.hidden = NO;
    }
}

- (void)scrollToThumberViewItem:(ViewItem *)item {
    if (!item) {
        return;
    }
    
    for (MetalRawdataRenderer *renderer in self.rendererArr) {
        if (renderer.isFullScreenDelegate) {
            continue;
        }
        if ([renderer.user.getUserId isEqualToString:item.userId]) {
            [[renderer.user getVideoPipe] subscribeWithDelegate:renderer resolution:ZoomInstantSDKVideoResolution_90];
        }
    }
}

- (void)pinMyself {
    ZoomInstantSDKUser *myUser = [[[ZoomInstantSDK shareInstance] getSession] getMySelf];
    for (ViewItem *item in self.bottomView.viewArray) {
        if ([myUser.getUserId isEqualToString:item.userId]) {
            [self pinThumberViewItem:item];
            [self.bottomView scrollToVisibleArea:item];
        }
    }
}

- (void)viewItemSelected:(ViewItem *)item {
    for (ViewItem *item in self.bottomView.viewArray) {
        item.view.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.5].CGColor;
    }
    
    item.view.layer.borderColor = [UIColor greenColor].CGColor;
}

- (void)startSpeakerTimer {
    if ([self.speakerTimer isValid]) {
        [self stopSpeakerTimer];
    }
    if (@available(iOS 10.0, *)) {
        self.speakerTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:NO
                                                              block:^(NSTimer * _Nonnull timer) {
                                                                  [self speakerOffAll];
                                                              }];
    } else {
        // Fallback on earlier versions
    }
}

- (void)stopSpeakerTimer {
    [self.speakerTimer invalidate];
    self.speakerTimer = nil;
}

- (void)speakerOffAll {
    [self.bottomView deactiveAllThumberView];
}

- (void)switchToShare:(SwitchBtn *)switchShareBtn {
    switchShareBtn.hidden = YES;
    
    if (!switchShareBtn.sharedUser) {
        return;
    }
    
    MetalRawdataRenderer *fullRenderer = [self getFullViewRenderer];
    if (fullRenderer.dataType == ZoomInstantSDKVideoType_ShareData) {
        [fullRenderer.user.getSharePipe unSubscribeWithDelegate:fullRenderer];
    } else {
        [fullRenderer.user.getVideoPipe unSubscribeWithDelegate:fullRenderer];
    }
    fullRenderer.user = switchShareBtn.sharedUser;
    fullRenderer.dataType = ZoomInstantSDKVideoType_ShareData;
    [switchShareBtn.sharedUser.getSharePipe subscribeWithDelegate:fullRenderer resolution:ZoomInstantSDKVideoResolution_720];
    [fullRenderer.metalView removeAvatar];
    
    for (ViewItem *item in self.bottomView.viewArray) {
        if ([switchShareBtn.sharedUser.getUserId isEqualToString:item.userId]) {
            [self viewItemSelected:item];
        }
    }
}

- (BOOL)creatFile:(NSString*)filePath{
    if (filePath.length==0) {
        return NO;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:filePath]) {
        return YES;
    }
    NSError *error;
    NSString *dirPath = [filePath stringByDeletingLastPathComponent];
    BOOL isSuccess = [fileManager createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:&error];

    if (!isSuccess) {
        return isSuccess;
    }
    isSuccess = [fileManager createFileAtPath:filePath contents:nil attributes:nil];
    return isSuccess;
}

- (BOOL)appendData:(NSData*)data withPath:(NSString *)filePath{
    if (filePath.length==0) {
        return NO;
    }
    BOOL result = [self creatFile:filePath];
    if (result) {
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:filePath];
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle synchronizeFile];
        [handle closeFile];
    }
    else{
        NSLog(@"appendData Failed");
    }
    return result;
}

#pragma mark - uialertview -
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    
    if (!self.joinSessionOrIgnorePasswordBlock) {
        return;
    }
    
    if (buttonIndex == alertView.firstOtherButtonIndex) {
        //Join
        NSString *password = [alertView textFieldAtIndex: 0].text;
        ZoomInstantSDKERROR error = self.joinSessionOrIgnorePasswordBlock(password, NO);
        if (error != Errors_Success) {
            [self showZoomPasswordAlert:YES];
        }
        NSLog(@"Input password error code : %@", @(error));
    } else if (buttonIndex == alertView.cancelButtonIndex) {
        //Cancel
        ZoomInstantSDKERROR error = self.joinSessionOrIgnorePasswordBlock(nil, YES);
        NSLog(@"Cancel error code : %@", @(error));
    }
}

#pragma mark - Notification -
- (void)keyBoardWillShow:(NSNotification *)notification {
    [self.chatInputView keyBoardWillShow:notification];
    self.chatView.hidden = NO;
    self.controlBarView.hidden = NO;
}

- (void)keyBoardDidShow:(NSNotification *)notification {
    [self.chatView updateFrame:NO notification:notification];
}

- (void)keyBoardWillHide:(NSNotification *)notification {
    [self.chatInputView keyBoardWillHide:notification];
}

- (void)keyBoardDidHide:(NSNotification *)notification {
    [self.chatView updateFrame:YES notification:notification];
}

- (void)onDeviceOrientationChangeNotification:(NSNotification *)aNotification {
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    if ((orientation == UIDeviceOrientationUnknown) || (orientation == UIDeviceOrientationFaceUp) || (orientation == UIDeviceOrientationFaceDown))
    {
        orientation = (UIDeviceOrientation)[[UIApplication sharedApplication] statusBarOrientation];
    }
    
    [[[ZoomInstantSDK shareInstance] getVideoHelper] rotateMyVideo:orientation];
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification {
    NSArray *allUserArray = [[[ZoomInstantSDK shareInstance] getSession] getAllUsers];
    MetalRawdataRenderer *fullRenderer = [self getFullViewRenderer];

    if (![allUserArray containsObject:fullRenderer.user]) {
        [self pinMyself];
    }
}
@end
