#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include "imgui.h"
#include "imgui_internal.h"
#include "imgui_impl_metal.h"

#include "font.hpp"
#include "logo.hpp"
#include "font_awesome.hpp"

// Состояния переключателей (готовы к хукам)
static bool g_wallbang = true;
static bool g_norecoil = true;
static bool g_bunnyhop = false;
static bool g_esp_box = true;
static bool g_esp_health = true;
static bool g_esp_nickname = true;
static bool g_offscreen = false;

// Для слайдера и комбо
static float g_slider_value = 0.0f;
static int g_combo_index = 0;
static ImVec4 g_color1 = ImVec4(0.0f, 1.0f, 0.0f, 1.0f); // зеленый
static ImVec4 g_color2 = ImVec4(1.0f, 0.0f, 0.0f, 1.0f); // красный

#pragma mark - Кастомные виджеты

void DrawLogoVector(ImDrawList* draw, ImVec2 center, float size) {
    float s = size;
    ImU32 glowColor = IM_COL32(234, 193, 251, 40);
    draw->AddCircleFilled(center, s * 1.2f, glowColor);
    
    ImVec2 p1(center.x - s * 0.3f, center.y - s * 0.55f);
    ImVec2 p2(center.x + s * 0.3f, center.y - s * 0.55f);
    ImVec2 p3(center.x + s * 0.7f, center.y + s * 0.55f);
    ImVec2 p4(center.x - s * 0.7f, center.y + s * 0.55f);
    draw->AddQuadFilled(p1, p2, p3, p4, IM_COL32(238, 238, 244, 255));
    
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
    float height = 32.0f;
    ImVec2 pos = window->DC.CursorPos;
    ImRect bb(pos, ImVec2(pos.x + width, pos.y + height));
    ImGui::ItemSize(bb);
    if (!ImGui::ItemAdd(bb, id)) return false;
    bool hovered, held;
    bool pressed = ImGui::ButtonBehavior(bb, id, &hovered, &held);
    if (pressed) *v = !(*v);
    
    ImDrawList* draw = ImGui::GetWindowDrawList();
    draw->AddRectFilled(bb.Min, bb.Max, IM_COL32(20, 20, 30, 255), 16.0f);
    draw->AddRect(bb.Min, bb.Max, IM_COL32(255, 255, 255, hovered ? 40 : 20), 16.0f, 0, 1.0f);
    draw->AddText(ImVec2(pos.x + 12, pos.y + 9), IM_COL32(235, 235, 242, 255), label);
    
    float swW = 28.0f, swH = 14.0f;
    ImVec2 swMin(bb.Max.x - swW - 10, pos.y + 9);
    ImVec2 swMax(swMin.x + swW, swMin.y + swH);
    ImU32 trackCol = *v ? IM_COL32(124, 92, 255, 255) : IM_COL32(40, 40, 55, 255);
    draw->AddRectFilled(swMin, swMax, trackCol, swH * 0.5f);
    float knobR = 6.0f;
    float knobX = *v ? (swMax.x - knobR - 2.0f) : (swMin.x + knobR + 2.0f);
    draw->AddCircleFilled(ImVec2(knobX, swMin.y + swH * 0.5f), knobR, IM_COL32(255, 255, 255, 255));
    
    return pressed;
}

// Кастомный слайдер с градиентом белый→розовый
void GradientSlider(const char* label, float* value, float min, float max, float width) {
    ImGuiWindow* window = ImGui::GetCurrentWindow();
    if (window->SkipItems) return;
    
    const ImGuiID id = window->GetID(label);
    ImVec2 pos = window->DC.CursorPos;
    float height = 20.0f;
    ImRect bb(pos, ImVec2(pos.x + width, pos.y + height));
    ImGui::ItemSize(bb);
    if (!ImGui::ItemAdd(bb, id)) return;
    
    bool hovered, held;
    bool pressed = ImGui::ButtonBehavior(bb, id, &hovered, &held);
    if (held) {
        float t = (ImGui::GetIO().MousePos.x - bb.Min.x) / bb.GetWidth();
        t = ImClamp(t, 0.0f, 1.0f);
        *value = min + t * (max - min);
    }
    
    ImDrawList* draw = ImGui::GetWindowDrawList();
    
    // Градиент белый→розовый
    int steps = 20;
    float step_w = bb.GetWidth() / steps;
    for (int i = 0; i < steps; i++) {
        float t = (float)i / steps;
        ImU32 col = ImLerp(IM_COL32(255, 255, 255, 255), IM_COL32(255, 182, 193, 255), t);
        draw->AddRectFilled(
            ImVec2(bb.Min.x + i * step_w, bb.Min.y),
            ImVec2(bb.Min.x + (i + 1) * step_w, bb.Max.y),
            col, 3.0f
        );
    }
    
    // Ползунок
    float t = (*value - min) / (max - min);
    float knob_x = bb.Min.x + t * bb.GetWidth();
    draw->AddCircleFilled(ImVec2(knob_x, bb.GetCenter().y), 8.0f, IM_COL32(255, 255, 255, 255));
    draw->AddCircle(ImVec2(knob_x, bb.GetCenter().y), 8.0f, IM_COL32(0, 0, 0, 100), 0, 1.5f);
    
    // Текст
    char buf[32];
    snprintf(buf, sizeof(buf), "%s >> %.0f", label, *value);
    draw->AddText(ImVec2(pos.x, pos.y + height + 4), IM_COL32(180, 180, 200, 255), buf);
}

// Colorpicker — два квадратика
void ColorPicker(const char* label, ImVec4* color1, ImVec4* color2) {
    ImGuiWindow* window = ImGui::GetCurrentWindow();
    if (window->SkipItems) return;
    
    ImVec2 pos = window->DC.CursorPos;
    float size = 16.0f;
    float spacing = 4.0f;
    
    ImDrawList* draw = ImGui::GetWindowDrawList();
    
    // Первый квадратик
    ImRect bb1(pos, ImVec2(pos.x + size, pos.y + size));
    ImGui::ItemSize(bb1);
    ImGui::ItemAdd(bb1, window->GetID(label));
    draw->AddRectFilled(bb1.Min, bb1.Max, ImGui::ColorConvertFloat4ToU32(*color1), 3.0f);
    draw->AddRect(bb1.Min, bb1.Max, IM_COL32(255, 255, 255, 60), 3.0f, 0, 1.0f);
    
    // Второй квадратик
    ImVec2 pos2(pos.x + size + spacing, pos.y);
    ImRect bb2(pos2, ImVec2(pos2.x + size, pos2.y + size));
    ImGui::ItemSize(bb2);
    ImGui::ItemAdd(bb2, window->GetID(label + 1));
    draw->AddRectFilled(bb2.Min, bb2.Max, ImGui::ColorConvertFloat4ToU32(*color2), 3.0f);
    draw->AddRect(bb2.Min, bb2.Max, IM_COL32(255, 255, 255, 60), 3.0f, 0, 1.0f);
    
    // Текст
    draw->AddText(ImVec2(pos.x, pos.y + size + 4), IM_COL32(180, 180, 200, 255), label);
}

void BeginCard(const char* title, float width, float height) {
    ImVec2 pos = ImGui::GetCursorScreenPos();
    ImDrawList* draw = ImGui::GetWindowDrawList();
    draw->AddRectFilled(pos, ImVec2(pos.x + width, pos.y + height), IM_COL32(18, 18, 28, 255), 8.0f);
    draw->AddRect(pos, ImVec2(pos.x + width, pos.y + height), IM_COL32(255, 255, 255, 25), 8.0f, 0, 1.0f);
    draw->AddText(ImVec2(pos.x + 12, pos.y + 10), IM_COL32(235, 235, 242, 255), title);
    draw->AddLine(ImVec2(pos.x, pos.y + 32), ImVec2(pos.x + width, pos.y + 32), IM_COL32(255, 255, 255, 20), 1.0f);
    ImGui::BeginChild(title, ImVec2(width, height), false, ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
    ImGui::SetCursorPos(ImVec2(12, 40));
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
    
    // Компактный размер как в оригинале
    CGFloat menuW = 480.0f;
    CGFloat menuH = 320.0f;
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
    
    ImFontConfig fontCfg;
    fontCfg.FontDataOwnedByAtlas = false;
    self.mainFont = io.Fonts->AddFontFromMemoryTTF(
        (void*)font_medium, sizeof(font_medium), 13.0f * scale, &fontCfg,
        io.Fonts->GetGlyphRangesCyrillic()
    );
    
    ImFontConfig logoCfg;
    logoCfg.FontDataOwnedByAtlas = false;
    self.logoFont = io.Fonts->AddFontFromMemoryTTF(
        (void*)logo_ttf, sizeof(logo_ttf), 42.0f * scale, &logoCfg
    );
    
    io.FontGlobalScale = 1.0f / scale;
    ImGui_ImplMetal_Init(self.device);
    
    self.selectedSidebarTab = 0;
    self.selectedTopTab = 0;
    self.isReady = YES;
    
    CGFloat buttonSize = 44.0f;
    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.frame = CGRectMake(screenSize.width - 60, 40, buttonSize, buttonSize);
    self.toggleButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.12 blue:0.25 alpha:0.9];
    self.toggleButton.layer.cornerRadius = 22;
    self.toggleButton.layer.borderWidth = 1;
    self.toggleButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
    [self.toggleButton setTitle:@"S" forState:UIControlStateNormal];
    [self.toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
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
    
    const float W = 480.0f;
    const float H = 320.0f;
    const float sidebarW = 110.0f;
    const float topbarH = 36.0f;
    
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0, 0));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 10.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1.0f);
    ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0.06f, 0.06f, 0.09f, 0.98f));
    ImGui::PushStyleColor(ImGuiCol_Border, ImVec4(1.0f, 1.0f, 1.0f, 0.1f));
    ImGui::SetNextWindowPos(ImVec2(0, 0), ImGuiCond_Always);
    ImGui::SetNextWindowSize(ImVec2(W, H), ImGuiCond_Always);
    
    // Скрытый скролл
    ImGuiWindowFlags flags = ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoCollapse |
                             ImGuiWindowFlags_NoTitleBar |
                             ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse;
    
    ImGui::Begin("##main_ui", nullptr, flags);
    
    ImDrawList* draw = ImGui::GetWindowDrawList();
    ImVec2 wp = ImGui::GetWindowPos();
    
    // Фон сайдбара
    draw->AddRectFilled(wp, ImVec2(wp.x + sidebarW, wp.y + H), IM_COL32(12, 12, 18, 255), 10.0f, ImDrawFlags_RoundCornersLeft);
    draw->AddLine(ImVec2(wp.x + sidebarW, wp.y), ImVec2(wp.x + sidebarW, wp.y + H), IM_COL32(255, 255, 255, 18), 1.0f);
    draw->AddLine(ImVec2(wp.x + sidebarW, wp.y + topbarH), ImVec2(wp.x + W, wp.y + topbarH), IM_COL32(255, 255, 255, 18), 1.0f);
    
    // Логотип обрезан сверху — рисуем через foreground draw list
    if (self.logoFont) {
        ImDrawList* fg = ImGui::GetForegroundDrawList();
        ImVec2 logoPos(wp.x + sidebarW * 0.5f, wp.y - 8.0f); // Y отрицательный = обрезан сверху
        ImGui::PushFont(self.logoFont);
        ImVec2 glyph_size = ImGui::CalcTextSize("A");
        fg->AddText(ImVec2(logoPos.x - glyph_size.x * 0.5f, logoPos.y),
                    IM_COL32(238, 238, 244, 255), "A");
        ImGui::PopFont();
    }
    
    // Табы сайдбара
    const char* sidebarItems[] = {"Visuals", "Combat", "World", "Movement", "Misc", "Configs"};
    ImGui::SetCursorPos(ImVec2(8, 50));
    ImGui::PushStyleVar(ImGuiStyleVar_ButtonTextAlign, ImVec2(0.0f, 0.5f));
    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(10, 0));
    ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 6.0f);
    for (int i = 0; i < 6; i++) {
        bool active = (self.selectedSidebarTab == i);
        ImGui::SetCursorPosX(8);
        ImGui::PushStyleColor(ImGuiCol_Button, active ? ImVec4(0.15f, 0.12f, 0.25f, 1.0f) : ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.18f, 0.15f, 0.28f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.20f, 0.17f, 0.30f, 1.0f));
        ImGui::PushStyleColor(ImGuiCol_Text, active ? ImVec4(0.95f, 0.95f, 0.98f, 1.0f) : ImVec4(0.55f, 0.55f, 0.62f, 1.0f));
        if (ImGui::Button(sidebarItems[i], ImVec2(sidebarW - 16, 30))) {
            self.selectedSidebarTab = i;
        }
        ImGui::PopStyleColor(4);
        ImGui::Dummy(ImVec2(0, 3));
    }
    ImGui::PopStyleVar(3);
    
    // Профиль внизу слева
    ImVec2 profilePos(wp.x + 8, wp.y + H - 36);
    draw->AddCircle(ImVec2(profilePos.x + 8, profilePos.y + 8), 7.0f, IM_COL32(255, 255, 255, 200), 0, 1.5f);
    draw->AddText(ImVec2(profilePos.x + 20, profilePos.y + 2), IM_COL32(235, 235, 242, 255), "@STANDLEO");
    draw->AddText(ImVec2(profilePos.x + 20, profilePos.y + 16), IM_COL32(255, 215, 0, 255), "Premium");
    
    // Верхние табы
    const char* topItems[] = {"General", "Advanced"};
    ImGui::SetCursorPos(ImVec2(sidebarW + 16, 8));
    for (int i = 0; i < 2; i++) {
        bool active = (self.selectedTopTab == i);
        ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0, 0, 0, 0));
        ImGui::PushStyleColor(ImGuiCol_Text, active ? ImVec4(0.95f, 0.95f, 0.98f, 1.0f) : ImVec4(0.50f, 0.50f, 0.58f, 1.0f));
        if (ImGui::Button(topItems[i], ImVec2(70, 22))) {
            self.selectedTopTab = i;
        }
        ImGui::PopStyleColor(4);
        ImGui::SameLine(0, 8);
    }
    
    // Плавное перетаскивание
    ImVec2 mousePos = ImGui::GetIO().MousePos;
    bool mouseInTitlebar = (mousePos.x >= sidebarW && mousePos.x <= W && mousePos.y >= 0 && mousePos.y <= topbarH);
    
    if (mouseInTitlebar && ImGui::IsMouseDown(0)) {
        if (!self.isDragging) {
            self.isDragging = YES;
            self.dragStartPos = CGPointMake(mousePos.x - self.menuOffset.x, mousePos.y - self.menuOffset.y);
        }
    }
    
    if (self.isDragging && ImGui::IsMouseDown(0)) {
        CGPoint newOffset = CGPointMake(mousePos.x - self.dragStartPos.x, mousePos.y - self.dragStartPos.y);
        self.menuOffset = newOffset;
        self.hostView.frame = CGRectMake(newOffset.x, newOffset.y, W, H);
    } else {
        self.isDragging = NO;
    }
    
    // Контент
    float contentStartX = sidebarW + 16;
    float contentStartY = topbarH + 12;
    float colWidth = (W - sidebarW - 32) * 0.5f;
    
    if (self.selectedSidebarTab == 0) { // Visuals
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginCard("Visuals", colWidth, 160.0f);
        RenderPillToggle("Box ESP", &g_esp_box, colWidth - 24.0f);
        RenderPillToggle("Health Bar", &g_esp_health, colWidth - 24.0f);
        RenderPillToggle("Nickname", &g_esp_nickname, colWidth - 24.0f);
        EndCard();
        
        ImGui::SetCursorPos(ImVec2(contentStartX + colWidth + 12, contentStartY));
        BeginCard("Settings", colWidth, 160.0f);
        RenderPillToggle("Offscreen", &g_offscreen, colWidth - 24.0f);
        EndCard();
    }
    else if (self.selectedSidebarTab == 1) { // Combat
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginCard("Combat", colWidth, 160.0f);
        RenderPillToggle("Wallbang", &g_wallbang, colWidth - 24.0f);
        RenderPillToggle("NoRecoil", &g_norecoil, colWidth - 24.0f);
        EndCard();
        
        ImGui::SetCursorPos(ImVec2(contentStartX + colWidth + 12, contentStartY));
        BeginCard("Category example", colWidth, 160.0f);
        RenderPillToggle("Simple switch", &g_esp_box, colWidth - 24.0f);
        ImGui::Dummy(ImVec2(0, 8));
        RenderPillToggle("Another toggle", &g_esp_health, colWidth - 24.0f);
        EndCard();
    }
    else if (self.selectedSidebarTab == 2) { // World
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginCard("World", colWidth * 2 + 12, 160.0f);
        GradientSlider("And slider??", &g_slider_value, 0.0f, 100.0f, colWidth * 2 - 24.0f);
        ImGui::Dummy(ImVec2(0, 20));
        ColorPicker("Colorpicker", &g_color1, &g_color2);
        EndCard();
    }
    else if (self.selectedSidebarTab == 3) { // Movement
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginCard("Movement", colWidth, 120.0f);
        RenderPillToggle("BunnyHop", &g_bunnyhop, colWidth - 24.0f);
        EndCard();
        
        ImGui::SetCursorPos(ImVec2(contentStartX + colWidth + 12, contentStartY));
        BeginCard("Combo", colWidth, 120.0f);
        const char* combo_items[] = {"First", "Second", "Third"};
        ImGui::SetCursorPosX(12);
        ImGui::PushItemWidth(colWidth - 24.0f);
        ImGui::Combo("##combo", &g_combo_index, combo_items, 3);
        ImGui::PopItemWidth();
        EndCard();
    }
    else if (self.selectedSidebarTab == 4) { // Misc
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginCard("Misc", colWidth * 2 + 12, 120.0f);
        RenderPillToggle("Toggle example", &g_esp_box, colWidth - 24.0f);
        ImGui::Dummy(ImVec2(0, 4));
        RenderPillToggle("Internal too?", &g_esp_health, colWidth - 24.0f);
        EndCard();
    }
    else if (self.selectedSidebarTab == 5) { // Configs
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        BeginCard("Configs", colWidth * 2 + 12, 120.0f);
        ImGui::SetCursorPosX(12);
        ImGui::TextColored(ImVec4(0.50f, 0.50f, 0.58f, 1.0f), "No configs yet");
        EndCard();
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
