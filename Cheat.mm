#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include "imgui.h"
#include "imgui_internal.h"
#include "imgui_impl_metal.h"

// Шрифты из репо
#include "font.hpp"
#include "logo.hpp"
#include "font_awesome.hpp"

// Состояния переключателей
static bool g_wallbang = true;
static bool g_norecoil = true;
static bool g_bunnyhop = false;
static bool g_esp_box = true;
static bool g_esp_health = true;
static bool g_esp_nickname = true;

#pragma mark - Кастомные элементы

void DrawLogoVector(ImDrawList* draw, ImVec2 center, float size) {
    float s = size;
    ImU32 glowColor = IM_COL32(234, 193, 251, 40);
    draw->AddCircleFilled(center, s * 1.2f, glowColor);
    
    ImVec2 p1(center.x - s * 0.3f, center.y - s * 0.55f);
    ImVec2 p2(center.x + s * 0.3f, center.y - s * 0.55f);
    ImVec2 p3(center.x + s * 0.7f, center.y + s * 0.55f);
    ImVec2 p4(center.x - s * 0.7f, center.y + s * 0.55f);
    draw->AddQuadFilled(p1, p2, p3, p4, IM_COL32(218, 221, 216, 255));
    
    ImU32 bg = IM_COL32(15, 14, 24, 255);
    draw->AddTriangleFilled(ImVec2(center.x - s * 0.7f, center.y - s * 0.1f),
        ImVec2(center.x - s * 0.4f, center.y + s * 0.1f),
        ImVec2(center.x - s * 0.7f, center.y + s * 0.25f), bg);
    draw->AddTriangleFilled(ImVec2(center.x + s * 0.7f, center.y - s * 0.1f),
        ImVec2(center.x + s * 0.4f, center.y + s * 0.1f),
        ImVec2(center.x + s * 0.7f, center.y + s * 0.25f), bg);
    draw->AddTriangleFilled(ImVec2(center.x, center.y + s * 0.05f),
        ImVec2(center.x - s * 0.25f, center.y + s * 0.55f),
        ImVec2(center.x + s * 0.25f, center.y + s * 0.55f), bg);
    draw->AddCircleFilled(ImVec2(center.x, center.y - s * 0.15f), s * 0.08f, bg);
}

bool RenderPillToggle(const char* label, bool* v, float width) {
    ImGuiWindow* window = ImGui::GetCurrentWindow();
    if (window->SkipItems) return false;
    const ImGuiID id = window->GetID(label);
    float height = 40.0f;
    ImVec2 pos = window->DC.CursorPos;
    ImRect bb(pos, ImVec2(pos.x + width, pos.y + height));
    ImGui::ItemSize(bb);
    if (!ImGui::ItemAdd(bb, id)) return false;
    bool hovered, held;
    bool pressed = ImGui::ButtonBehavior(bb, id, &hovered, &held);
    if (pressed) *v = !(*v);
    
    ImDrawList* draw = ImGui::GetWindowDrawList();
    draw->AddRectFilled(bb.Min, bb.Max, IM_COL32(20, 20, 30, 255), 20.0f);
    draw->AddRect(bb.Min, bb.Max, IM_COL32(255, 255, 255, hovered ? 40 : 20), 20.0f, 0, 1.0f);
    draw->AddText(ImVec2(pos.x + 16, pos.y + 12), IM_COL32(235, 235, 242, 255), label);
    
    float swW = 32.0f, swH = 18.0f;
    ImVec2 swMin(bb.Max.x - swW - 14, pos.y + 11);
    ImVec2 swMax(swMin.x + swW, swMin.y + swH);
    ImU32 trackCol = *v ? IM_COL32(124, 92, 255, 255) : IM_COL32(40, 40, 55, 255);
    draw->AddRectFilled(swMin, swMax, trackCol, swH * 0.5f);
    float knobR = 7.0f;
    float knobX = *v ? (swMax.x - knobR - 2.0f) : (swMin.x + knobR + 2.0f);
    draw->AddCircleFilled(ImVec2(knobX, swMin.y + swH * 0.5f), knobR, IM_COL32(255, 255, 255, 255));
    
    return pressed;
}

void BeginCard(const char* title, float width, float height) {
    ImVec2 pos = ImGui::GetCursorScreenPos();
    ImDrawList* draw = ImGui::GetWindowDrawList();
    draw->AddRectFilled(pos, ImVec2(pos.x + width, pos.y + height), IM_COL32(18, 18, 28, 255), 10.0f);
    draw->AddRect(pos, ImVec2(pos.x + width, pos.y + height), IM_COL32(255, 255, 255, 25), 10.0f, 0, 1.0f);
    draw->AddText(ImVec2(pos.x + 16, pos.y + 14), IM_COL32(235, 235, 242, 255), title);
    draw->AddLine(ImVec2(pos.x, pos.y + 42), ImVec2(pos.x + width, pos.y + 42), IM_COL32(255, 255, 255, 20), 1.0f);
    ImGui::BeginChild(title, ImVec2(width, height), false, ImGuiWindowFlags_NoScrollbar);
    ImGui::SetCursorPos(ImVec2(16, 52));
}

void EndCard() { ImGui::EndChild(); }

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
@property (nonatomic, assign) CGPoint menuOffset;
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, assign) CGPoint dragStartPos;
@property (nonatomic, assign) ImFont* mainFont;
@property (nonatomic, assign) ImFont* logoFont;
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
    
    CGFloat menuW = 580.0f;
    CGFloat menuH = 360.0f;
    CGFloat posX = (screenSize.width - menuW) * 0.5f;
    CGFloat posY = (screenSize.height - menuH) * 0.5f;
    
    self.menuOffset = CGPointMake(posX, posY);
    
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
    
    // === ЕДИНСТВЕННЫЙ блок загрузки шрифтов ===
    ImFontConfig fontCfg;
    fontCfg.FontDataOwnedByAtlas = false;
    self.mainFont = io.Fonts->AddFontFromMemoryTTF(
        (void*)font_medium,
        sizeof(font_medium),
        14.0f * scale,
        &fontCfg,
        io.Fonts->GetGlyphRangesCyrillic()
    );
    
    ImFontConfig logoCfg;
    logoCfg.FontDataOwnedByAtlas = false;
    self.logoFont = io.Fonts->AddFontFromMemoryTTF(
        (void*)logo_ttf,
        sizeof(logo_ttf),
        48.0f * scale,
        &logoCfg
    );
    
    io.FontGlobalScale = 1.0f / scale;
    // === конец блока загрузки шрифтов ===
    
    ImGui_ImplMetal_Init(self.device);
    
    self.selectedSidebarTab = 3;
    self.selectedTopTab = 0;
    self.isReady = YES;
    
    CGFloat buttonSize = 50.0f;
    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.frame = CGRectMake(screenSize.width - 70, 40, buttonSize, buttonSize);
    self.toggleButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.12 blue:0.25 alpha:0.9];
    self.toggleButton.layer.cornerRadius = 25;
    self.toggleButton.layer.borderWidth = 1;
    self.toggleButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
    [self.toggleButton setTitle:@"S" forState:UIControlStateNormal];
    [self.toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    [self.toggleButton addTarget:self action:@selector(toggleMenu:) forControlEvents:UIControlEventTouchUpInside];
    [keyWindow addSubview:self.toggleButton];
    
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(render)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    NSLog(@"[Cheat] GUI ready with custom fonts");
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
    
    const float W = 580.0f;
    const float H = 360.0f;
    const float sidebarW = 140.0f;
    const float topbarH = 48.0f;
    
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0, 0));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 12.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1.0f);
    ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0.06f, 0.06f, 0.09f, 0.98f));
    ImGui::PushStyleColor(ImGuiCol_Border, ImVec4(1.0f, 1.0f, 1.0f, 0.1f));
    ImGui::SetNextWindowPos(ImVec2(0, 0), ImGuiCond_Always);
    ImGui::SetNextWindowSize(ImVec2(W, H), ImGuiCond_Always);
    ImGui::Begin("##main_ui", nullptr,
        ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse |
        ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar);
    
    ImDrawList* draw = ImGui::GetWindowDrawList();
    ImVec2 wp = ImGui::GetWindowPos();
    
    draw->AddRectFilled(wp, ImVec2(wp.x + sidebarW, wp.y + H), IM_COL32(12, 12, 18, 255), 12.0f, ImDrawFlags_RoundCornersLeft);
    draw->AddLine(ImVec2(wp.x + sidebarW, wp.y), ImVec2(wp.x + sidebarW, wp.y + H), IM_COL32(255, 255, 255, 18), 1.0f);
    draw->AddLine(ImVec2(wp.x + sidebarW, wp.y + topbarH), ImVec2(wp.x + W, wp.y + topbarH), IM_COL32(255, 255, 255, 18), 1.0f);
    
    if (self.logoFont) {
        ImGui::PushFont(self.logoFont);
        ImVec2 glyph_size = ImGui::CalcTextSize("A");
        ImGui::SetCursorPos(ImVec2(sidebarW * 0.5f - glyph_size.x * 0.5f, 18.0f));
        ImGui::TextColored(ImVec4(0.95f, 0.95f, 0.98f, 1.0f), "A");
        ImGui::PopFont();
    } else {
        DrawLogoVector(draw, ImVec2(wp.x + sidebarW * 0.5f, wp.y + 42.0f), 28.0f);
    }
    
    const char* sidebarItems[] = {"Visuals", "Combat", "World", "Movement", "Misc", "Configs", "Inventory"};
    ImGui::SetCursorPos(ImVec2(12, 82));
    ImGui::PushStyleVar(ImGuiStyleVar_ButtonTextAlign, ImVec2(0.0f, 0.5f));
    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(14, 0));
    ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 8.0f);
    for (int i = 0; i < 7; i++) {
        bool active = (self.selectedSidebarTab == i);
        ImGui::SetCursorPosX(12);
        ImGui::PushStyleColor(ImGuiCol_Button, active ? ImVec4(0.15f, 0.12f, 0.25f, 1.0f) : ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.18f, 0.15f, 0.28f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.20f, 0.17f, 0.30f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_Text, active ? ImVec4(0.95f, 0.95f, 0.98f, 1.0f) : ImVec4(0.55f, 0.55f, 0.62f, 1.0f));
        if (ImGui::Button(sidebarItems[i], ImVec2(sidebarW - 24, 36))) {
            self.selectedSidebarTab = i;
        }
        ImGui::PopStyleColor(4);
        ImGui::Dummy(ImVec2(0, 4));
    }
    ImGui::PopStyleVar(3);
    
    const char* topItems[] = {"General", "Advanced"};
    ImGui::SetCursorPos(ImVec2(sidebarW + 20, 12));
    for (int i = 0; i < 2; i++) {
        bool active = (self.selectedTopTab == i);
        ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_Text, active ? ImVec4(0.95f, 0.95f, 0.98f, 1.0f) : ImVec4(0.50f, 0.50f, 0.58f, 1.0f));
        if (ImGui::Button(topItems[i], ImVec2(80, 24))) {
            self.selectedTopTab = i;
        }
        ImGui::PopStyleColor(4);
        ImGui::SameLine(0, 12);
    }
    
    ImVec2 mousePos = ImGui::GetIO().MousePos;
    bool mouseInTitlebar = (mousePos.x >= sidebarW && mousePos.x <= W && mousePos.y >= 0 && mousePos.y <= topbarH);
    
    if (mouseInTitlebar && ImGui::IsMouseDown(0)) {
        if (!self.isDragging) {
            self.isDragging = YES;
            self.dragStartPos = CGPointMake(mousePos.x - self.menuOffset.x, mousePos.y - self.menuOffset.y);
        }
        CGPoint newOffset = CGPointMake(mousePos.x - self.dragStartPos.x, mousePos.y - self.dragStartPos.y);
        self.menuOffset = newOffset;
        self.hostView.frame = CGRectMake(newOffset.x, newOffset.y, W, H);
    } else {
        self.isDragging = NO;
    }
    
    float contentStartX = sidebarW + 20;
    float contentStartY = topbarH + 20;
    float colWidth = (W - sidebarW - 40) * 0.5f;
    
    if (self.selectedSidebarTab == 0) {
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginCard("ESP", colWidth, 200.0f);
        RenderPillToggle("Box ESP", &g_esp_box, colWidth - 32.0f);
        RenderPillToggle("Health Bar", &g_esp_health, colWidth - 32.0f);
        RenderPillToggle("Nickname", &g_esp_nickname, colWidth - 32.0f);
        EndCard();
    }
    else if (self.selectedSidebarTab == 1) {
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginCard("Combat", colWidth, 200.0f);
        RenderPillToggle("Wallbang", &g_wallbang, colWidth - 32.0f);
        RenderPillToggle("NoRecoil", &g_norecoil, colWidth - 32.0f);
        EndCard();
    }
    else if (self.selectedSidebarTab == 3) {
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginCard("Movement", colWidth, 120.0f);
        RenderPillToggle("BunnyHop", &g_bunnyhop, colWidth - 32.0f);
        EndCard();
    }
    else if (self.selectedSidebarTab == 4) {
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginCard("Misc", colWidth, 120.0f);
        RenderPillToggle("Offscreen", &g_esp_box, colWidth - 32.0f);
        EndCard();
    }
    else {
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        ImGui::TextColored(ImVec4(0.50f, 0.50f, 0.58f, 1.0f), "%s: coming soon", sidebarItems[self.selectedSidebarTab]);
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
