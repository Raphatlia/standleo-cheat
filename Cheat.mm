#import <UIKit/UIKit.h>

@interface CheatWindow : UIWindow
@property (nonatomic, assign) NSInteger tapCount;
@property (nonatomic, assign) NSTimeInterval lastTap;
@property (nonatomic, strong) UIView *panel;
@end

@implementation CheatWindow

- (void)sendEvent:(UIEvent *)event {
    if (event.type == UIEventTypeTouches) {
        UITouch *touch = event.allTouches.anyObject;
        if (touch.phase == UITouchPhaseEnded) {
            CGPoint loc = [touch locationInView:self];
            CGPoint center = CGPointMake(self.bounds.size.width/2, self.bounds.size.height/2);
            CGFloat dist = hypot(loc.x - center.x, loc.y - center.y);
            
            // Тап в центре (радиус 60px)
            if (dist < 60) {
                NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
                if (now - self.lastTap > 1.5) self.tapCount = 0;
                self.lastTap = now;
                self.tapCount++;
                
                if (self.tapCount >= 3) {
                    self.tapCount = 0;
                    [self togglePanel];
                    return; // не передаём тап игре
                }
            }
        }
    }
    [super sendEvent:event]; // передаём тап игре
}

- (void)togglePanel {
    if (self.panel && self.panel.superview) {
        [self.panel removeFromSuperview];
        self.panel = nil;
        return;
    }
    
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
    
    [self addSwitch:p label:@"Wallbang"  y:45  tag:1];
    [self addSwitch:p label:@"NoRecoil"  y:80  tag:2];
    
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(70, 160, 120, 36);
    [close setTitle:@"Скрыть" forState:UIControlStateNormal];
    close.backgroundColor = [UIColor systemRedColor];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    close.layer.cornerRadius = 8;
    [close addTarget:self action:@selector(hidePanel) forControlEvents:UIControlEventTouchUpInside];
    [p addSubview:close];
    
    [p addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)]];
    
    [self addSubview:p];
    self.panel = p;
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

- (void)onSwitch:(UISwitch*)sw {
    NSLog(@"[Cheat] switch %ld = %d", (long)sw.tag, sw.on);
    // сюда потом добавим реальные патчи
}

- (void)hidePanel { [self.panel removeFromSuperview]; self.panel = nil; }

- (void)panPanel:(UIPanGestureRecognizer*)r {
    CGPoint t=[r translationInView:r.view.superview];
    r.view.center=CGPointMake(r.view.center.x+t.x, r.view.center.y+t.y);
    [r setTranslation:CGPointMake(0,0) inView:r.view.superview];
}

@end

// Точка входа
__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        CheatWindow *cw = [[CheatWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        cw.windowLevel = UIWindowLevelAlert + 1;
        cw.hidden = NO;
        cw.userInteractionEnabled = YES;
        NSLog(@"[Cheat] window ready — тапни 3 раза в центр экрана");
    });
}
