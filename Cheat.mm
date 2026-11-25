#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "imgui.h"
#import "imgui_impl_metal.h"

@interface CheatManager : NSObject
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, assign) BOOL showMenu;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, assign) BOOL imguiInitialized;
@property (nonatomic, assign) CGFloat framebufferWidth;
@property (nonatomic, assign) CGFloat framebufferHeight;
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

    self.device = MTLCreateSystemDefaultDevice();
    self.commandQueue = [self.device newCommandQueue];
    
    self.metalLayer = [CAMetalLayer layer];
    self.metalLayer.device = self.device;
    self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalLayer.framebufferOnly = YES;
    self.metalLayer.frame = win.bounds;
    self.metalLayer.contentsScale = [UIScreen mainScreen].scale;
    [win.layer addSublayer:self.metalLayer];
    
    self.framebufferWidth = win.bounds.size.width * [UIScreen mainScreen].scale;
    self.framebufferHeight = win.bounds.size.height * [UIScreen mainScreen].scale;
    
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(self.framebufferWidth, self.framebufferHeight);
    io.DisplayFramebufferScale = ImVec2([UIScreen mainScreen].scale, [UIScreen mainScreen].scale);
    
    ImGui_ImplMetal_Init(self.device);
    self.imguiInitialized = YES;
    
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(win.bounds.size.width-80, 60, 60, 60);
    b.backgroundColor = [UIColor colorWithRed:1 green:0 blue:0 alpha:0.75];
    b.layer.cornerRadius = 30;
    [b setTitle:@"⚙️" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:26];
    [b addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:b];
    self.button = b;
    
    NSLog(@"[Cheat] ImGui + Metal ready");
}

- (void)toggle:(UIButton*)x {
    self.showMenu = !self.showMenu;
    NSLog(@"[Cheat] menu %@", self.showMenu ? @"shown" : @"hidden");
}

- (void)renderImGui {
    if (!self.imguiInitialized || !self.showMenu) return;
    
    id<CAMetalDrawable> drawable = [self.metalLayer nextDrawable];
    if (!drawable) return;
    
    MTLRenderPassDescriptor *passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    passDesc.colorAttachments[0].texture = drawable.texture;
    passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    
    ImGui_ImplMetal_NewFrame(passDesc);
    ImGui::NewFrame();
    
    ImGui::Begin("STANDLEO CHEAT");
    ImGui::Text("Wallbang: ON");
    ImGui::Text("NoRecoil: ON");
    ImGui::Checkbox("BunnyHop", nullptr);
    ImGui::End();
    
    ImGui::Render();
    
    id<MTLCommandBuffer> cmdBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [cmdBuffer renderCommandEncoderWithDescriptor:passDesc];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cmdBuffer, encoder);
    [encoder endEncoding];
    [cmdBuffer presentDrawable:drawable];
    [cmdBuffer commit];
}

@end
