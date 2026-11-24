#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

@interface CheatManager : NSObject
@property (nonatomic, strong) UIButton *button;
@end

@implementation CheatManager

static CheatManager *g = nil;

+ (CheatManager *)shared {
    if (!g) g = [[CheatManager alloc] init];
    return g;
}

+ (void)load {
    // Ретраи: пробуем 15 раз каждые 1 секунду
    for (int i = 1; i <= 15; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[CheatManager shared] trySetup];
        });
    }
}

- (UIWindow *)findWindow {
    // iOS 27: keyWindow deprecated, ищем через connectedScenes
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)s;
        for (UIWindow *w in ws.windows) {
            if (w.isKeyWindow) return w;
        }
        if (ws.windows.count > 0) return ws.windows.firstObject;
    }
    return nil;
}

- (void)trySetup {
    if (self.button) return; // уже есть
    
    UIWindow *win = [self findWindow];
    if (!win) {
        NSLog(@"[Cheat] no window yet");
        return;
    }
    
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(20, 150, 60, 60);
    b.backgroundColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.7];
    b.layer.cornerRadius = 30;
    [b setTitle:@"⚙️" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:24];
    [b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [b addGestureRecognizer:pan];
    
    [win addSubview:b];
    self.button = b;
    NSLog(@"[Cheat] BUTTON ADDED!");
}

- (void)tap:(UIButton *)x {
    NSLog(@"[Cheat] tapped");
}

- (void)pan:(UIPanGestureRecognizer *)r {
    CGPoint t = [r translationInView:r.view.superview];
    r.view.center = CGPointMake(r.view.center.x + t.x, r.view.center.y + t.y);
    [r setTranslation:CGPointMake(0, 0) inView:r.view.superview];
}

@end
