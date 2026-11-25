#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include "imgui.h"
#include "imgui_internal.h"
#include "imgui_impl_metal.h"

// Состояния UI-переключателей
static bool g_offscreen_enabled = true;
static bool g_option_two = false;
static float g_slider_val = 65.0f;

// Реальные функции чита
static bool g_wallbang = true;
static bool g_norecoil = true;
static bool g_bunnyhop = false;
static bool g_esp_box = true;
static bool g_esp_health = true;
static bool g_esp_nickname = true;

#pragma mark - Кастомные элементы отрисовки

void DrawBrandLogo(ImDrawList* draw, ImVec2 center) {
    ImU32 white = IM_COL32(238, 238, 244, 255);
    ImU32 bg = IM_COL32(15, 14, 24, 255);
    
    ImVec2 p1(center.x - 6, center.y - 11);
    ImVec2 p2(center.x + 6, center.y - 11);
    ImVec2 p3(center.x + 14, center.y + 11);
    ImVec2 p4(center.x - 14, center.y + 11);
    draw->AddQuadFilled(p1, p2, p3, p4, white);
    
    draw->AddTriangleFilled(ImVec2(center.x - 14, center.y - 2),
        ImVec2(center.x - 8, center.y + 2),
        ImVec2(center.x - 14, center.y + 5), bg);
    draw->AddTriangleFilled(ImVec2(center.x + 14, center.y - 2),
        ImVec2(center.x + 8, center.y + 2),
        ImVec2(center.x + 14, center.y + 5), bg);
    draw->AddTriangleFilled(ImVec2(center.x, center.y + 1),
        ImVec2(center.x - 5, center.y + 11),
        ImVec2(center.x + 5, center.y + 11), bg);
    draw->AddCircleFilled(ImVec2(center.x, center.y - 4), 2.0f, bg);
}

bool RenderCardToggle(const char* title, const char* subtitle, bool* v, float width) {
    ImGuiWindow* window = ImGui::GetCurrentWindow();
    if (window->SkipItems) return false;
    const ImGuiID id = window->GetID(title);
    float height = 62.0f;
    ImVec2 pos = window->DC.CursorPos;
    ImRect bb(pos, ImVec2(pos.x + width, pos.y + height));
    ImGui::ItemSize(bb);
    if (!ImGui::ItemAdd(bb, id)) return false;
    bool hovered, held;
    bool pressed = ImGui::ButtonBehavior(bb, id, &hovered, &held);
    if (pressed) *v = !(*v);
    ImDrawList* draw = ImGui::GetWindowDrawList();
    draw->AddRectFilled(bb.Min, bb.Max, IM_COL32(19, 18, 30, 255), 6.0f);
    draw->AddRect(bb.Min, bb.Max, IM_COL32(255, 255, 255, hovered ? 32 : 18), 6.0f, 0, 1.0f);
    draw->AddText(ImVec2(pos.x + 14, pos.y + 12), IM_COL32(235, 235, 242, 255), title);
    draw->AddText(ImVec2(pos.x + 14, pos.y + 34), IM_COL32(125, 125, 140, 255), subtitle);
    float swW = 32.0f;
    float swH = 16.0f;
    ImVec2 swMin(bb.Max.x - swW - 14, pos.y + 12);
    ImVec2 swMax(swMin.x + swW, swMin.y + swH);
    ImU32 trackCol = *v ? IM_COL32(238, 238, 245, 255) : IM_COL32(32, 30, 46, 255);
    draw->AddRectFilled(swMin, swMax, trackCol, swH * 0.5f);
    draw->AddRect(swMin, swMax, IM_COL32(255, 255, 255, 25), swH * 0.5f);
    float knobR = 5.0f;
    float knobX = *v ? (swMax.x - knobR - 3.0f) : (swMin.x + knobR + 3.0f);
    ImU32 knobCol = *v ? IM_COL32(15, 14, 24, 255) : IM_COL32(130, 130, 145, 255);
    draw->AddCircleFilled(ImVec2(knobX, swMin.y + swH * 0.5f), knobR, knobCol);
    return pressed;
}

void BeginSectionCard(const char* title, float width, float height) {
    ImVec2 pos = ImGui::GetCursorScreenPos();
    ImDrawList* draw = ImGui::GetWindowDrawList();
    draw->AddRectFilled(pos, ImVec2(pos.x + width, pos.y + height), IM_COL32(16, 15, 26, 255), 8.0f);
    draw->AddRect(pos, ImVec2(pos.x + width, pos.y + height), IM_COL32(255, 255, 255, 20), 8.0f, 0, 1.0f);
    draw->AddText(ImVec2(pos.x + 14, pos.y + 12), IM_COL32(235, 235, 242, 255), title);
    draw->AddLine(ImVec2(pos.x, pos.y + 38), ImVec2(pos.x + width, pos.y + 38), IM_COL32(255, 255, 255, 16), 1.0f);
    ImGui::BeginChild(title, ImVec2(width, height), false, ImGuiWindowFlags_NoScrollbar);
    ImGui::SetCursorPos(ImVec2(12, 48));
}

void EndSectionCard() {
    ImGui::EndChild();
}

#pragma mark - Metal Host View

@interface UIOverlayHostView : UIView
@end

@implementation UIOverlayHostView
+ (Class)layerClass { return [CAMetalLayer class]; }
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint p = [[touches anyObject] locationInView:self];
    ImGui::GetIO().MousePos = ImVec2(p.x, p.y);
    ImGui::GetIO().MouseDown[0] = true;
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint p = [[touches anyObject] locationInView:self];
    ImGui::GetIO().MousePos = ImVec2(p.x, p.y);
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    ImGui::GetIO().MouseDown[0] = false;
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    ImGui::GetIO().MouseDown[0] = false;
}
@end

#pragma mark - Manager

@interface AntisocialGUIManager : NSObject
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) UIOverlayHostView *hostView;
@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) BOOL isReady;
@property (nonatomic, assign) BOOL isMenuVisible;
@property (nonatomic, assign) int selectedSidebarTab;
@property (nonatomic, assign) int selectedTopTab;
@end

@implementation AntisocialGUIManager

static AntisocialGUIManager *sharedInstance = nil;

+ (AntisocialGUIManager *)shared {
    if (!sharedInstance) sharedInstance = [[AntisocialGUIManager alloc] init];
    return sharedInstance;
}

+ (void)load {
    for (int i = 1; i <= 15; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                [[AntisocialGUIManager shared] trySetup];
            });
    }
}

- (UIWindow *)findKeyWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
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
    
    CGFloat menuW = 620.0f;
    CGFloat menuH = 380.0f;
    CGFloat posX = MAX(10.0f, (screenSize.width - menuW) * 0.5f);
    CGFloat posY = MAX(20.0f, (screenSize.height - menuH) * 0.5f);
    
    self.hostView = [[UIOverlayHostView alloc] initWithFrame:CGRectMake(posX, posY, menuW, menuH)];
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
    self.metalLayer.drawableSize = CGSizeMake(menuW * scale, menuH * scale);
    
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2(menuW, menuH);
    io.DisplayFramebufferScale = ImVec2(scale, scale);
    io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange;
    ImGui_ImplMetal_Init(self.device);
    
    self.selectedSidebarTab = 0;
    self.selectedTopTab = 0;
    self.isReady = YES;
    
    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.frame = CGRectMake(screenSize.width - 70, 40, 48, 48);
    self.toggleButton.backgroundColor = [UIColor colorWithRed:0.08 green:0.07 blue:0.13 alpha:0.9];
    self.toggleButton.layer.cornerRadius = 24;
    self.toggleButton.layer.borderWidth = 1;
    self.toggleButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;
    [self.toggleButton setTitle:@"A" forState:UIControlStateNormal];
    [self.toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    [self.toggleButton addTarget:self action:@selector(toggleMenu:) forControlEvents:UIControlEventTouchUpInside];
    [keyWindow addSubview:self.toggleButton];
    
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(render)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    NSLog(@"[Cheat] Antisocial GUI ready");
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
    
    const float W = 620.0f;
    const float H = 380.0f;
    const float sidebarW = 148.0f;
    const float topbarH = 48.0f;
    
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0, 0));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 10.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1.0f);
    ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0.051f, 0.047f, 0.086f, 0.99f));
    ImGui::PushStyleColor(ImGuiCol_Border, ImVec4(1.0f, 1.0f, 1.0f, 0.08f));
    ImGui::SetNextWindowPos(ImVec2(0, 0), ImGuiCond_Always);
    ImGui::SetNextWindowSize(ImVec2(W, H), ImGuiCond_Always);
    ImGui::Begin("##main_ui", nullptr,
        ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse |
        ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar);
    
    ImDrawList* draw = ImGui::GetWindowDrawList();
    ImVec2 wp = ImGui::GetWindowPos();
    
    // Фон сайдбара
    draw->AddRectFilled(wp, ImVec2(wp.x + sidebarW, wp.y + H), IM_COL32(15, 14, 24, 255), 10.0f, ImDrawFlags_RoundCornersLeft);
    draw->AddLine(ImVec2(wp.x + sidebarW, wp.y), ImVec2(wp.x + sidebarW, wp.y + H), IM_COL32(255, 255, 255, 16), 1.0f);
    draw->AddLine(ImVec2(wp.x + sidebarW, wp.y + topbarH), ImVec2(wp.x + W, wp.y + topbarH), IM_COL32(255, 255, 255, 16), 1.0f);
    
    // Логотип
    DrawBrandLogo(draw, ImVec2(wp.x + sidebarW * 0.5f, wp.y + 42.0f));
    
    // Навигация сайдбара
    const char* sidebarItems[] = {"Visuals", "Combat", "World", "Movement", "Misc", "Configs", "Inventory"};
    ImGui::SetCursorPos(ImVec2(12, 82));
    ImGui::PushStyleVar(ImGuiStyleVar_ButtonTextAlign, ImVec2(0.0f, 0.5f));
    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(14, 0));
    ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 6.0f);
    for (int i = 0; i < 7; i++) {
        bool active = (self.selectedSidebarTab == i);
        ImGui::SetCursorPosX(12);
        ImGui::PushStyleColor(ImGuiCol_Button, active ? ImVec4(1, 1, 1, 0.06f) : ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(1, 1, 1, 0.05f));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(1, 1, 1, 0.08f));
        ImGui::PushStyleColor(ImGuiCol_Text, active ? ImVec4(0.95f, 0.95f, 0.98f, 1.0f) : ImVec4(0.50f, 0.50f, 0.58f, 1.0f));
        if (ImGui::Button(sidebarItems[i], ImVec2(sidebarW - 24, 32))) {
            self.selectedSidebarTab = i;
        }
        ImGui::PopStyleColor(4);
        ImGui::Dummy(ImVec2(0, 2));
    }
    ImGui::PopStyleVar(3);
    
    // Верхние вкладки
    const char* topItems[] = {"General", "Advanced"};
    ImGui::SetCursorPos(ImVec2(sidebarW + 18, 12));
    for (int i = 0; i < 2; i++) {
        bool active = (self.selectedTopTab == i);
        ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_Text, active ? ImVec4(0.95f, 0.95f, 0.98f, 1.0f) : ImVec4(0.48f, 0.48f, 0.56f, 1.0f));
        if (ImGui::Button(topItems[i], ImVec2(80, 24))) {
            self.selectedTopTab = i;
        }
        ImGui::PopStyleColor(4);
        ImGui::SameLine(0, 8);
    }
    
    // Контент
    float contentStartX = sidebarW + 18;
    float contentStartY = topbarH + 18;
    float colWidth = (W - sidebarW - 18 * 3) * 0.5f;
    
    if (self.selectedSidebarTab == 0) { // Visuals
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginSectionCard("ESP Demo", colWidth, 180.0f);
        RenderCardToggle("Box ESP", "Draws box around enemies", &g_esp_box, colWidth - 24.0f);
        RenderCardToggle("Health Bar", "Shows health indicator", &g_esp_health, colWidth - 24.0f);
        RenderCardToggle("Nickname", "Shows player names", &g_esp_nickname, colWidth - 24.0f);
        EndSectionCard();
        
        ImGui::SetCursorPos(ImVec2(contentStartX + colWidth + 18, contentStartY));
        BeginSectionCard("Preview", colWidth, 180.0f);
        ImVec2 boxPos = ImGui::GetCursorScreenPos();
        float boxW = colWidth - 24.0f;
        float boxH = 36.0f;
        draw->AddRectFilled(boxPos, ImVec2(boxPos.x + boxW, boxPos.y + boxH), IM_COL32(19, 18, 30, 255), 6.0f);
        draw->AddRect(boxPos, ImVec2(boxPos.x + boxW, boxPos.y + boxH), IM_COL32(255, 255, 255, 18), 6.0f, 0, 1.0f);
        draw->AddText(ImVec2(boxPos.x + 12, boxPos.y + 11), IM_COL32(130, 130, 145, 255), "ESP preview placeholder");
        EndSectionCard();
    }
    else if (self.selectedSidebarTab == 1) { // Combat
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginSectionCard("Combat Settings", colWidth, 180.0f);
        RenderCardToggle("Wallbang", "Shoot through walls", &g_wallbang, colWidth - 24.0f);
        RenderCardToggle("NoRecoil", "Zero weapon recoil", &g_norecoil, colWidth - 24.0f);
        EndSectionCard();
        
        ImGui::SetCursorPos(ImVec2(contentStartX + colWidth + 18, contentStartY));
        BeginSectionCard("Status", colWidth, 180.0f);
        ImVec2 statusPos = ImGui::GetCursorScreenPos();
        draw->AddText(ImVec2(statusPos.x + 12, statusPos.y + 12), IM_COL32(130, 130, 145, 255), "Wallbang:");
        draw->AddText(ImVec2(statusPos.x + 120, statusPos.y + 12), 
            g_wallbang ? IM_COL32(100, 255, 100, 255) : IM_COL32(255, 100, 100, 255),
            g_wallbang ? "ON" : "OFF");
        draw->AddText(ImVec2(statusPos.x + 12, statusPos.y + 36), IM_COL32(130, 130, 145, 255), "NoRecoil:");
        draw->AddText(ImVec2(statusPos.x + 120, statusPos.y + 36),
            g_norecoil ? IM_COL32(100, 255, 100, 255) : IM_COL32(255, 100, 100, 255),
            g_norecoil ? "ON" : "OFF");
        EndSectionCard();
    }
    else if (self.selectedSidebarTab == 3) { // Movement
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginSectionCard("Movement", colWidth, 120.0f);
        RenderCardToggle("BunnyHop", "Auto jump on landing", &g_bunnyhop, colWidth - 24.0f);
        EndSectionCard();
    }
    else if (self.selectedSidebarTab == 4) { // Misc
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginSectionCard("Misc", colWidth, 120.0f);
        RenderCardToggle("Offscreen", "Shows indicators out of view", &g_offscreen_enabled, colWidth - 24.0f);
        EndSectionCard();
    }
    else {
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginSectionCard(sidebarItems[self.selectedSidebarTab], colWidth * 2 + 18, 120.0f);
        draw->AddText(ImVec2(contentStartX + 12, contentStartY + 60), 
            IM_COL32(130, 130, 145, 255), "Coming soon");
        EndSectionCard();
    }
    
    ImGui::End();
    ImGui::PopStyleColor(2);
    ImGui::PopStyleVar(3);
    
    ImGui::Render();
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, encoder);
    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

@end
