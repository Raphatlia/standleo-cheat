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

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint p = [touch locationInView:self];
    ImGui::GetIO().MousePos = ImVec2(p.x, p.y);
    ImGui::GetIO().MouseDown[0] = true;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint p = [touch locationInView:self];
    ImGui::GetIO().MousePos = ImVec2(p.x, p.y);
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    ImGui::GetIO().MouseDown[0] = false;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    ImGui::GetIO().MouseDown[0] = false;
}
@end

@interface CheatManager : NSObject
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) CheatHostView *hostView;
@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) BOOL isReady;
@property (nonatomic, assign) BOOL isMenuVisible;
@property (nonatomic, assign) int selectedTab;
@end

@implementation CheatManager

static CheatManager *sharedInstance = nil;

+ (CheatManager *)shared {
    if (!sharedInstance) {
        sharedInstance = [[CheatManager alloc] init];
    }
    return sharedInstance;
}

+ (void)load {
    for (int i = 1; i <= 20; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[CheatManager shared] trySetup];
        });
    }
}

- (UIWindow *)findKeyWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return nil;
}

- (void)trySetup {
    if (self.hostView) return;
    
    UIWindow *keyWindow = [self findKeyWindow];
    if (!keyWindow) return;
    
    CGFloat scale = [UIScreen mainScreen].scale;
    CGSize screenSize = keyWindow.bounds.size;
    
    self.hostView = [[CheatHostView alloc] initWithFrame:CGRectMake(10, 120, 380, 320)];
    self.hostView.backgroundColor = [UIColor clearColor];
    self.hostView.hidden = YES;
    self.hostView.userInteractionEnabled = NO;
    [keyWindow addSubview:self.hostView];
    
    self.device = MTLCreateSystemDefaultDevice();
    self.commandQueue = [self.device newCommandQueue];
    
    self.metalLayer = (CAMetalLayer *)self.hostView.layer;
    self.metalLayer.device = self.device;
    self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalLayer.framebufferOnly = NO;
    self.metalLayer.opaque = NO;
    self.metalLayer.backgroundColor = [UIColor clearColor].CGColor;
    self.metalLayer.contentsScale = scale;
    self.metalLayer.drawableSize = CGSizeMake(380 * scale, 320 * scale);
    
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2(380, 320);
    io.DisplayFramebufferScale = ImVec2(scale, scale);
    io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange;
    
    ImGui_ImplMetal_Init(self.device);
    
    // Тёмная тема
    ImGuiStyle &style = ImGui::GetStyle();
    style.WindowRounding = 10.0f;
    style.ChildRounding = 8.0f;
    style.FrameRounding = 6.0f;
    style.WindowPadding = ImVec2(12, 12);
    style.ItemSpacing = ImVec2(8, 6);
    style.WindowBorderSize = 1.0f;
    
    ImVec4 *colors = style.Colors;
    colors[ImGuiCol_Text] = ImVec4(0.90f, 0.90f, 0.90f, 1.0f);
    colors[ImGuiCol_WindowBg] = ImVec4(0.05f, 0.05f, 0.08f, 0.95f);
    colors[ImGuiCol_ChildBg] = ImVec4(0.08f, 0.08f, 0.12f, 0.90f);
    colors[ImGuiCol_Border] = ImVec4(0.20f, 0.20f, 0.25f, 1.0f);
    colors[ImGuiCol_CheckMark] = ImVec4(0.50f, 0.40f, 1.0f, 1.0f);
    colors[ImGuiCol_SliderGrab] = ImVec4(0.50f, 0.40f, 1.0f, 1.0f);
    
    self.isReady = YES;
    
    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.frame = CGRectMake(screenSize.width - 80, 60, 60, 60);
    self.toggleButton.backgroundColor = [UIColor colorWithRed:0.50 green:0.40 blue:1.0 alpha:0.85];
    self.toggleButton.layer.cornerRadius = 30;
    self.toggleButton.layer.borderWidth = 2;
    self.toggleButton.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.toggleButton setTitle:@"⚡" forState:UIControlStateNormal];
    self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:26];
    [self.toggleButton addTarget:self action:@selector(toggleMenu:) forControlEvents:UIControlEventTouchUpInside];
    [keyWindow addSubview:self.toggleButton];
    
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(render)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    NSLog(@"[Cheat] GUI ready");
}

- (void)toggleMenu:(UIButton *)button {
    self.isMenuVisible = !self.isMenuVisible;
    self.hostView.hidden = !self.isMenuVisible;
    self.hostView.userInteractionEnabled = self.isMenuVisible;
    
    if (!self.isMenuVisible) {
        ImGui::GetIO().MouseDown[0] = false;
        ImGui::GetIO().MousePos = ImVec2(-FLT_MAX, -FLT_MAX);
    }
}

- (void)render {
    if (!self.isReady || !self.isMenuVisible) return;
    
    id<CAMetalDrawable> drawable = [self.metalLayer nextDrawable];
    if (!drawable) return;
    
    MTLRenderPassDescriptor *renderPass = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPass.colorAttachments[0].texture = drawable.texture;
    renderPass.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPass.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    
    ImGui_ImplMetal_NewFrame(renderPass);
    ImGui::NewFrame();
    
    ImGui::SetNextWindowPos(ImVec2(0, 0), ImGuiCond_Always);
    ImGui::SetNextWindowSize(ImVec2(380, 320), ImGuiCond_Always);
    ImGui::Begin("##main", nullptr,
                 ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse |
                 ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar);
    
    // Сайдбар
    ImGui::BeginChild("sidebar", ImVec2(100, 0), true);
    ImGui::Text("STANDLEO");
    ImGui::Separator();
    ImGui::Spacing();
    
    const char *tabs[] = {"Combat", "Visual", "Misc"};
    for (int i = 0; i < 3; i++) {
        bool isSelected = (self.selectedTab == i);
        if (ImGui::Selectable(tabs[i], isSelected, 0, ImVec2(80, 30))) {
            self.selectedTab = i;
        }
    }
    ImGui::EndChild();
    ImGui::SameLine();
    
    // Контент
    ImGui::BeginChild("content", ImVec2(0, 0), true);
    
    if (self.selectedTab == 0) {
        ImGui::Text("Combat");
        ImGui::Separator();
        ImGui::Checkbox("Wallbang", &g_wallbang);
        ImGui::Checkbox("NoRecoil", &g_norecoil);
    }
    else if (self.selectedTab == 1) {
        ImGui::Text("Visual");
        ImGui::Separator();
        ImGui::Text("Coming soon");
    }
    else {
        ImGui::Text("Misc");
        ImGui::Separator();
        ImGui::Checkbox("BunnyHop", &g_bunnyhop);
    }
    
    ImGui::EndChild();
    ImGui::End();
    
    ImGui::Render();
    
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, encoder);
    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

@end
