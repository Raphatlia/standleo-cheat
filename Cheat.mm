#import <UIKit/UIKit.h>

@interface CheatManager : NSObject
@property (nonatomic, strong) UIButton *button;
@end

@implementation CheatManager
static CheatManager *g = nil;
+ (CheatManager*)shared { if(!g) g=[[CheatManager alloc] init]; return g; }

+ (void)load {
    for (int i=1;i<=15;i++)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(i*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [[CheatManager shared] trySetup]; });
}

- (UIWindow*)findWindow {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene*)s).windows)
            if (w.isKeyWindow) return w;
        if (((UIWindowScene*)s).windows.count) return ((UIWindowScene*)s).windows.firstObject;
    }
    return nil;
}

- (void)trySetup {
    if (self.button) return;
    UIWindow *win = [self findWindow];
    if (!win) return;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(20,150,60,60);
    b.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.7];
    b.layer.cornerRadius = 30;
    [b setTitle:@"⚙️" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:24];
    [b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
    [b addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
    [win addSubview:b];
    self.button = b;
}
- (void)tap:(UIButton*)x { NSLog(@"[Cheat] tap"); }
- (void)pan:(UIPanGestureRecognizer*)r {
    CGPoint t=[r translationInView:r.view.superview];
    r.view.center=CGPointMake(r.view.center.x+t.x, r.view.center.y+t.y);
    [r setTranslation:CGPointZero inView:r.view.superview];
}
@end
