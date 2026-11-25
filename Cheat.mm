#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import "imgui.h"
#import "imgui_impl_metal.h"

@interface CheatOverlayView : UIView
@end
@implementation CheatOverlayView
+ (Class)layerClass { return [CAMetalLayer class]; }
@end

@interface CheatManager : NSObject
@property (nonatomic, strong) UIWindow *overlay;
@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> cmdQueue;
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, assign) BOOL showMenu;
@property (nonatomic, assign) BOOL ready;
@end

@implementation CheatManager

static CheatManager *g = nil;
+ (CheatManager*)shared { if(!g) g=[[CheatManager alloc] init]; return g; }

+ (void)load {
    for (int i=1;i<=20;i++)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(i*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [[CheatManager shared] trySetup]; });
}

- (UIWindow*)keyWin {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene*)s).windows) if (w.isKeyWindow) return w;
    }
    return nil;
}

- (void)trySetup {
    if (self.overlay) return;
    UIWindow *win = [self keyWin];
    if (!win) return;

    // Оверлей-окно поверх Unity
    self.overlay = [[UIWindow alloc] initWithFrame:win.bounds];
    self.overlay.windowLevel = UIWindowLevelAlert + 1;
    self.overlay.backgroundColor = [UIColor clearColor];
    self.overlay.userInteractionEnabled = YES;

    CheatOverlayView *ov = [[CheatOverlayView alloc] initWithFrame:win.bounds];
    ov.backgroundColor = [UIColor clearColor];
    [self.overlay addSubview:ov];

    self.device = MTLCreateSystemDefaultDevice();
    self.cmdQueue = [self.device newCommandQueue];

    self.metalLayer = (CAMetalLayer*)ov.layer;
    self.metalLayer.device = self.device;
    self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalLayer.framebufferOnly = NO;   // ← важно: можно читать/смешивать
    self.metalLayer.opaque = NO;            // ← прозрачный, Unity виден сквозь
    self.metalLayer.frame = win.bounds;
    self.metalLayer.contentsScale = [UIScreen mainScreen].scale;
    self.metalLayer.drawableSize = CGSizeMake(win.bounds.size.width*[UIScreen mainScreen].scale,
                                               win.bounds.size.height*[UIScreen mainScreen].scale);

    ImGui::CreateContext();
    ImGui_ImplMetal_Init(self.device);
    self.ready = YES;

    // Кнопка-триггер (в том же оверлей-окне → поверх всего)
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(win.bounds.size.width-80, 60, 60, 60);
    b.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.75];
    b.layer.cornerRadius = 30;
    b.layer.borderWidth = 2;
    b.layer.borderColor = [UIColor whiteColor].CGColor;
    [b setTitle:@"⚙️" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:26];
    [b addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
    [self.overlay addSubview:b];
    self.button = b;

    self.overlay.hidden = NO;
    NSLog(@"[Cheat] ImGui overlay ready");
}

- (void)toggle:(UIButton*)x { self.showMenu = !self.showMenu; }

- (void)render {
    if (!self.ready) return;
    id<CAMetalDrawable> d = [self.metalLayer nextDrawable];
    if (!d) return;

    MTLRenderPassDescriptor *pd = [MTLRenderPassDescriptor new];
    pd.colorAttachments[0].texture = d.texture;
    pd.colorAttachments[0].loadAction = MTLLoadActionClear;
    pd.colorAttachments[0].storeAction = MTLStoreActionStore;
    pd.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0); // прозрачный фон

    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(self.metalLayer.drawableSize.width, self.metalLayer.drawableSize.height);
    io.DisplayFramebufferScale = ImVec2([UIScreen mainScreen].scale, [UIScreen mainScreen].scale);

    ImGui_ImplMetal_NewFrame(pd);
    ImGui::NewFrame();
    if (self.showMenu) {
        ImGui::SetNextWindowPos(ImVec2(40,120), ImGuiCond_FirstUseEver);
        ImGui::Begin("STANDLEO");
        ImGui::Checkbox("Wallbang", nullptr);
        ImGui::Checkbox("NoRecoil", nullptr);
        ImGui::Checkbox("BunnyHop", nullptr);
        ImGui::End();
    }
    ImGui::Render();

    id<MTLCommandBuffer> cb = [self.cmdQueue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:pd];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cb, enc);
    [enc endEncoding];
    [cb presentDrawable:d];
    [cb commit];
}

@end

// Цикл рендера оверлея
__attribute__((constructor)) static void startLoop() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:[CheatManager shared] selector:@selector(render)];
        [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    });
}
