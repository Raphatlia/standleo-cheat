#import <UIKit/UIKit.h>
#import <dlfcn.h>

// Простая функция инициализации, которая вызывается при загрузке dylib
__attribute__((constructor))
static void init() {
    NSLog(@"[Cheat] Dylib загружен успешно!");
    
    // Ждём 2 секунды, чтобы главное окно игры успело создаться
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = UIApplication.sharedApplication.keyWindow;
        if (!keyWindow) {
            NSLog(@"[Cheat] Не удалось найти keyWindow");
            return;
        }
        
        // Создаём простую кнопку для теста
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, 100, 60, 60);
        btn.backgroundColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.7];
        btn.layer.cornerRadius = 30;
        [btn setTitle:@"⚙️" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:24];
        
        // Делаем кнопку перетаскиваемой (базовая функция меню)
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:btn action:@selector(handlePan:)];
        [btn addGestureRecognizer:pan];
        
        [keyWindow addSubview:btn];
        NSLog(@"[Cheat] Кнопка добавлена на экран!");
    });
}

// Обработчик перетаскивания для кнопки
@implementation UIButton (Draggable)
- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    CGPoint translation = [recognizer translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [recognizer setTranslation:CGPointZero inView:self.superview];
}
@end
