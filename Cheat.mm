#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import "imgui.h"
#import "imgui_impl_metal.h"

static bool g_wallbang = true;
static bool g_norecoil = true;
static bool g_bunnyhop = false;

@interface CheatHostView : UIView
@end

@implementation CheatHostView
+ (Class)layerClass { return [CAMetalLayer class]; }

- (void)touchesBegan:(NSSet*)t withEvent:(UIEvent*)e {
    CGPoint p = [[t anyObject] locationInView:self];
    CGFloat s = [UIScreen mainScreen].scale;
    ImGuiIO& io = ImGui::GetIO();
    io.MousePos = ImVec2(p.x*s, p.y*s);
    io.MouseDown[0] = true;
}
- (void)touchesMoved:(NSSet*)t withEvent:(UIEvent*)e {
    CGPoint p = [[t anyObject] locationInView:self];
    CGFloat s = [UIScreen mainScreen].scale;
    ImGui::GetIO().MousePos = ImVec2(p.x*s, p.y*s);
}
- (void)touchesEnded:(NSSet*)t withEvent:(UIEvent*)e {
    ImGui::GetIO().MouseDown[0] = false;
}
- (void)touchesCancelled:(NSSet*)t withEvent:(UIEvent*)e {
    ImGui::GetIO().MouseDown[0] = false;
}
@end

@interface CheatManager : NSObject
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, strong) CheatHostView *host;
@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> cmdQueue;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, assign) BOOL ready;
@property (nonatomic, assign) BOOL showMenu;
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
    if (self.host) return;
    UIWindow *win = [self keyWin];
    if (!win) return;

    CGFloat scale = [UIScreen mainScreen].scale;

    // Хост только под меню (не на весь экран → логин/тапы игры не перехватываются)
    self.host = [[CheatHostView alloc] initWithFrame:CGRectMake(10,120,320,240)];
    self.host.backgroundColor = [UIColor clearColor];
    self.host.hidden = YES;
    self.host.userInteractionEnabled = NO;
    [win addSubview:self.host];

    self.device = MTLCreateSystemDefaultDevice();
    self.cmdQueue = [self.device newCommandQueue];

    self.metalLayer = (CAMetalLayer*)self.host.layer;
    self.metalLayer.device = self.device;
    self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalLayer.framebufferOnly = NO;
    self.metalLayer.opaque = NO;
    self.metalLayer.backgroundColor = [UIColor clearColor].CGColor;
    self.metalLayer.contentsScale = scale;
    self.metalLayer.drawableSize = CGSizeMake(320*scale, 240*scale);

    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(320*scale, 240*scale);
    io.DisplayFramebufferScale = ImVec2(scale, scale);
    io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange;
    ImGui_ImplMetal_Init(self.device);
    self.ready = YES;

    // Кнопка show/hide в правом верхнем углу (вне зоны хоста)
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(win.bounds.size.width-80, 60, 60, 60);
    b.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.75];
    b.layer.cornerRadius = 30;
    b.layer.borderWidth = 2;
    b.layer.borderColor = [UIColor whiteColor].CGColor;
    [b setTitle:@"⚙️" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:26];
    [b addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:b];
    self.button = b;

    // Постоянный рендер-цикл (рисуем только когда меню открыто)
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(render)];
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];

    NSLog(@"[Cheat] ImGui live GUI ready");
}

- (void)toggle:(UIButton*)x {
    self.showMenu = !self.showMenu;
    self.host.hidden = !self.showMenu;
    self.host.userInteractionEnabled = self.showMenu;
    if (!self.showMenu) {
        ImGuiIO& io = ImGui::GetIO();
        io.MouseDown[0] = false;
        io.MousePos = ImVec2(-FLT_MAX,-FLT_MAX);
    }
}

- (void)render {
    if (!self.ready || !self.showMenu) return;
    id<CAMetalDrawable> d = [self.metalLayer nextDrawable];
    if (!d) return;

    MTLRenderPassDescriptor *pd = [MTLRenderPassDescriptor renderPassDescriptor];
    pd.colorAttachments[0].texture = d.texture;
    pd.colorAttachments[0].loadAction = MTLLoadActionClear;
    pd.colorAttachments[0].storeAction = MTLStoreActionStore;
    pd.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0);

    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(self.metalLayer.drawableSize.width,
                            self.metalLayer.drawableSize.height);

    ImGui_ImplMetal_NewFrame(pd);
    ImGui::NewFrame();

    ImGui::SetNextWindowPos(ImVec2(0,0), ImGuiCond_Always);
    ImGui::SetNextWindowSize(ImVec2(self.metalLayer.drawableSize.width,
                                    self.metalLayer.drawableSize.height), ImGuiCond_Always);
    ImGui::Begin("STANDLEO", nullptr,
        ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse |
        ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoBringToFrontOnFocus);
    ImGui::Text("STANDLEO CHEAT");
    ImGui::Separator();
    ImGui::Checkbox("Wallbang", &g_wallbang);
    ImGui::Checkbox("NoRecoil", &g_norecoil);
    ImGui::Checkbox("BunnyHop", &g_bunnyhop);
    ImGui::End();

    ImGui::Render();
    id<MTLCommandBuffer> cb = [self.cmdQueue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:pd];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cb, enc);
    [enc endEncoding];
    [cb presentDrawable:d];
    [cb commit];
}

@end
