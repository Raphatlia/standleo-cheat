#import <UIKit/UIKit.h>

@interface CheatManager : NSObject
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, strong) UIView *panel;
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

    // ВИДИМАЯ кнопка в правом верхнем углу (не мешает игре!)
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(win.bounds.size.width-80, 60, 60, 60);
    b.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.75];
    b.layer.cornerRadius = 30;
    b.layer.borderWidth = 2;
    b.layer.borderColor = [UIColor whiteColor].CGColor;
    [b setTitle:@"⚙️" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:26];
    [b addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
    [b addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]];
    [win addSubview:b];
    self.button = b;
}

- (void)toggle:(UIButton*)x {
    if (self.panel && self.panel.superview) {
        [self.panel removeFromSuperview];
        self.panel = nil;
        return;
    }
    UIWindow *win = [self findWindow];
    if (!win) return;

    UIView *p = [[UIView alloc] initWithFrame:CGRectMake(30, 140, 270, 230)];
    p.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.95];
    p.layer.cornerRadius = 14;
    p.layer.borderWidth = 1;
    p.layer.borderColor = [UIColor systemRedColor].CGColor;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0,10,270,24)];
    title.text = @"STANDLEO CHEAT";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:16];
    [p addSubview:title];

    [self addSwitch:p label:@"Wallbang" y:45 tag:1];
    [self addSwitch:p label:@"NoRecoil" y:80 tag:2];
    [self addSwitch:p label:@"BunnyHop" y:115 tag:3];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(75, 165, 120, 36);
    [close setTitle:@"Скрыть" forState:UIControlStateNormal];
    close.backgroundColor = [UIColor systemRedColor];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    close.layer.cornerRadius = 8;
    [close addTarget:self action:@selector(hide:) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:close];

    [win addSubview:p];
    self.panel = p;
}

- (void)addSwitch:(UIView*)p label:(NSString*)name y:(CGFloat)y tag:(NSInteger)tag {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16,y,150,28)];
    l.text = name; l.textColor = [UIColor whiteColor]; l.font = [UIFont systemFontOfSize:15];
    [p addSubview:l];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(205,y,50,28)];
    sw.tag = tag;
    [sw addTarget:self action:@selector(onSwitch:) forControlEvents:UIControlEventValueChanged];
    [p addSubview:sw];
}

- (void)onSwitch:(UISwitch*)sw { NSLog(@"[Cheat] switch %ld = %d",(long)sw.tag,sw.on); }
- (void)hide:(UIButton*)x { [self.panel removeFromSuperview]; self.panel = nil; }

- (void)pan:(UIPanGestureRecognizer*)r {
    CGPoint t=[r translationInView:r.view.superview];
    r.view.center=CGPointMake(r.view.center.x+t.x, r.view.center.y+t.y);
    [r setTranslation:CGPointMake(0,0) inView:r.view.superview];
}

@end
