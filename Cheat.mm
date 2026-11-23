#import <UIKit/UIKit.h>

@interface CheatManager : NSObject
@property (nonatomic, strong) UIButton *button;
@end

@implementation CheatManager

static CheatManager *g_manager = nil;

+ (CheatManager *)shared {
    if (!g_manager) g_manager = [[CheatManager alloc] init];
    return g_manager;
}

+ (void)load {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[CheatManager shared] setup];
    });
}

- (void)setup {
    UIWindow *keyWindow = UIApplication.sharedApplication.keyWindow;
    if (!keyWindow) return;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(20, 100, 60, 60);
    btn.backgroundColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.7];
    btn.layer.cornerRadius = 30;
    [btn setTitle:@"⚙️" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:24];
    [btn addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];

    [keyWindow addSubview:btn];
    self.button = btn;
    NSLog(@"[Cheat] Button added");
}

- (void)tapped:(UIButton *)b {
    NSLog(@"[Cheat] tapped");
}

@end
