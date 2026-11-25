#import <UIKit/UIKit.h>

@interface CheatManager : NSObject
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, assign) NSInteger tapCount;
@property (nonatomic, assign) NSTimeInterval lastTap;
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

    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(win.bounds.size.width/2 - 50, win.bounds.size.height/2 - 50, 100, 100);
    b.backgroundColor = [UIColor clearColor];
    b.alpha = 0.01; // Почти невидимая, но реагирует на тапы
    [b setTitle:@"⚙️" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:20];
    [b setTitleColor:[UIColor colorWithWhite:1 alpha:0.1] forState:UIControlStateNormal];
    [b addTarget:self action:@selector(onTap:) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:b];
    self.button = b;
    NSLog(@"[Cheat] center button added");
}

- (void)onTap:(UIButton*)btn {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - self.lastTap > 1.0) self.tapCount = 0;
    self.lastTap = now;
    self.tapCount++;
    
    NSLog(@"[Cheat] tap %ld", (long)self.tapCount);
    
    if (self.tapCount >= 2) { // 2 быстрых тапа по центру
        self.tapCount = 0;
        [self togglePanel];
    }
}

- (void)togglePanel {
    if (self.panel && self.panel.superview) {
        [self.panel removeFromSuperview];
        self.panel = nil;
        return;
    }
    UIWindow *win = [self findWindow];
    if (!win) return;

    UIView *p = [[UIView alloc] initWithFrame:CGRectMake(40, 120, 260, 220)];
    p.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
    p.layer.cornerRadius = 14;
    p.layer.borderWidth = 1;
    p.layer.borderColor = [UIColor systemRedColor].CGColor;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0,10,260,24)];
    title.text = @"STANDLEO CHEAT";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:16];
    [p addSubview:title];

    [self addSwitch:p label:@"Wallbang" y:45 tag:1];
    [self addSwitch:p label:@"NoRecoil" y:80 tag:2];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(70, 160, 120, 36);
    [close setTitle:@"Скрыть" forState:UIControlStateNormal];
    close.backgroundColor = [UIColor systemRedColor];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    close.layer.cornerRadius = 8;
    [close addTarget:self action:@selector(hide:) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:close];

    [win addSubview:p];
    self.panel = p;
    NSLog(@"[Cheat] panel shown");
}

- (void)addSwitch:(UIView*)p label:(NSString*)name y:(CGFloat)y tag:(NSInteger)tag {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16,y,140,28)];
    l.text = name; l.textColor = [UIColor whiteColor]; l.font = [UIFont systemFontOfSize:15];
    [p addSubview:l];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(200,y,50,28)];
    sw.tag = tag;
    [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
    [p addSubview:sw];
}

- (void)onSwitch:(UISwitch*)sw { NSLog(@"[Cheat] switch %ld = %d",(long)sw.tag,sw.on); }
- (void)hide:(UIButton*)x { [self.panel removeFromSuperview]; self.panel = nil; }

@end
