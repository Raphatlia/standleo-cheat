#include <UIKit/UIKit.h>
#include <dlfcn.h>

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 
                   dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = UIApplication.sharedApplication.keyWindow;
        if (!keyWindow) return;
        
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 100, 60, 60);
        btn.backgroundColor = [UIColor redColor];
        btn.layer.cornerRadius = 30;
        [btn setTitle:@"⚙" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:24];
        
        [btn addTarget:nil action:@selector(cheatButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        
        [keyWindow addSubview:btn];
        NSLog(@"[Cheat] Button added!");
    });
}

void cheatButtonTapped() {
    NSLog(@"[Cheat] Button tapped!");
}
