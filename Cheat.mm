#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include "imgui.h"
#include "imgui_internal.h"
#include "imgui_impl_metal.h"
#include "font_awesome.hpp"
#include "logo.hpp"
#include "medium.hpp"

// Глобальные переменные для функций
static bool g_wallbang = true;
static bool g_norecoil = true;
static bool g_bunnyhop = false;
static bool g_esp_box = true;
static bool g_esp_health = true;
static bool g_esp_nickname = true;

// Аниматор для плавных переходов
class c_animator {
    std::any value;
    std::chrono::steady_clock::time_point last_update;
public:
    c_animator(float initial) : value(initial), last_update(std::chrono::steady_clock::now()) {}
    void set(float to_value) { value = to_value; last_update = std::chrono::steady_clock::now(); }
    float get() const { return std::any_cast<float>(value); }
    void update(float to_value, float duration) {
        auto now = std::chrono::steady_clock::now();
        float delta = std::chrono::duration<float>(now - last_update).count();
        last_update = now;
        float current = std::any_cast<float>(value);
        float new_value = current + (to_value - current) * (delta / duration);
        value = new_value;
    }
};

#pragma mark - Кастомные виджеты

namespace elem {
    // Pill-тумблер с анимацией
    bool toggle(const char* label, bool* v, const char* description = "") {
        ImGuiWindow* window = ImGui::GetCurrentWindow();
        if (window->SkipItems) return false;
        const ImGuiID id = window->GetID(label);
        float height = 44.0f;
        ImVec2 pos = window->DC.CursorPos;
        ImRect bb(pos, ImVec2(pos.x + ImGui::GetContentRegionAvail().x, pos.y + height));
        ImGui::ItemSize(bb);
        if (!ImGui::ItemAdd(bb, id)) return false;
        bool hovered, held;
        bool pressed = ImGui::ButtonBehavior(bb, id, &hovered, &held);
        if (pressed) *v = !(*v);
        
        ImDrawList* draw = ImGui::GetWindowDrawList();
        // Фон карточки
        draw->AddRectFilled(bb.Min, bb.Max, IM_COL32(19, 18, 30, 255), 8.0f);
        draw->AddRect(bb.Min, bb.Max, IM_COL32(255, 255, 255, hovered ? 32 : 18), 8.0f, 0, 1.0f);
        
        // Текст
        draw->AddText(ImVec2(pos.x + 14, pos.y + 12), IM_COL32(235, 235, 242, 255), label);
        if (description[0]) {
            draw->AddText(ImVec2(pos.x + 14, pos.y + 28), IM_COL32(125, 125, 140, 255), description);
        }
        
        // Переключатель справа
        float swW = 32.0f;
        float swH = 18.0f;
        ImVec2 swMin(bb.Max.x - swW - 14, pos.y + 13);
        ImVec2 swMax(swMin.x + swW, swMin.y + swH);
        ImU32 trackCol = *v ? IM_COL32(238, 238, 245, 255) : IM_COL32(32, 30, 46, 255);
        draw->AddRectFilled(swMin, swMax, trackCol, swH * 0.5f);
        float knobR = 7.0f;
        float knobX = *v ? (swMax.x - knobR - 2.0f) : (swMin.x + knobR + 2.0f);
        ImU32 knobCol = *v ? IM_COL32(15, 14, 24, 255) : IM_COL32(130, 130, 145, 255);
        draw->AddCircleFilled(ImVec2(knobX, swMin.y + swH * 0.5f), knobR, knobCol);
        
        return pressed;
    }
    
    // Категория (collapsible секция)
    bool simple_category(const char* label) {
        ImGui::Spacing();
        ImGui::TextColored(ImVec4(0.85f, 0.85f, 0.92f, 1.0f), "%s", label);
        ImGui::Separator();
        return true;
    }
    
    void end_category() {
        ImGui::Spacing();
    }
}

#pragma mark - Векторный логотип "A"

void DrawLogoGradient(ImDrawList* draw, ImVec2 center, float size) {
    float s = size;
    
    // Свечение
    ImU32 glowColor = IM_COL32(234, 193, 251, 40);
    draw->AddCircleFilled(center, s * 1.2f, glowColor);
    
    // Основная форма "A"
    ImVec2 p1(center.x - s * 0.3f, center.y - s * 0.55f);
    ImVec2 p2(center.x + s * 0.3f, center.y - s * 0.55f);
    ImVec2 p3(center.x + s * 0.7f, center.y + s * 0.55f);
    ImVec2 p4(center.x - s * 0.7f, center.y + s * 0.55f);
    
    // Градиент от белого к фиолетовому
    ImU32 col1 = IM_COL32(218, 221, 216, 255);
    ImU32 col2 = IM_COL32(234, 193, 251, 255);
    draw->AddQuadFilled(p1, p2, p3, p4, col1);
    
    // Вырезы
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
    
    // Загружаем шрифты
    io.Fonts->AddFontFromMemoryTTF(instrument_sans_medium_ttf, sizeof(instrument_sans_medium_ttf), 13.0f * 2.0f, nullptr, io.Fonts->GetGlyphRangesCyrillic());
    io.FontGlobalScale = 0.5f;
    
    ImGui_ImplMetal_Init(self.device);
    
    self.selectedSidebarTab = 3; // Movement по умолчанию
    self.selectedTopTab = 0;
    self.isReady = YES;
    
    // Кнопка переключения
    CGFloat buttonSize = 50.0f;
    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.frame = CGRectMake(screenSize.width - 70, 40, buttonSize, buttonSize);
    self.toggleButton.backgroundColor = [UIColor colorWithRed:0.08 green:0.07 blue:0.13 alpha:0.9];
    self.toggleButton.layer.cornerRadius = 25;
    self.toggleButton.layer.borderWidth = 1;
    self.toggleButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
    [self.toggleButton setTitle:@"A" forState:UIControlStateNormal];
    [self.toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
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
    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 12.0f);
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
    draw->AddRectFilled(wp, ImVec2(wp.x + sidebarW, wp.y + H), IM_COL32(15, 14, 24, 255), 12.0f, ImDrawFlags_RoundCornersLeft);
    draw->AddLine(ImVec2(wp.x + sidebarW, wp.y), ImVec2(wp.x + sidebarW, wp.y + H), IM_COL32(255, 255, 255, 16), 1.0f);
    draw->AddLine(ImVec2(wp.x + sidebarW, wp.y + topbarH), ImVec2(wp.x + W, wp.y + topbarH), IM_COL32(255, 255, 255, 16), 1.0f);
    
    // Векторный логотип "A" с градиентом
    DrawLogoGradient(draw, ImVec2(wp.x + sidebarW * 0.5f, wp.y + 42.0f), 28.0f);
    
    // Навигация сайдбара
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
        ImGui::PushStyleColor(ImGuiCol_Text, active ? ImVec4(0.95f, 0.95f, 0.98f, 1.0f) : ImVec4(0.50f, 0.50f, 0.58f, 1.0f));
        if (ImGui::Button(sidebarItems[i], ImVec2(sidebarW - 24, 36))) {
            self.selectedSidebarTab = i;
        }
        ImGui::PopStyleColor(4);
        ImGui::Dummy(ImVec2(0, 4));
    }
    ImGui::PopStyleVar(3);
    
    // Верхние вкладки
    const char* topItems[] = {"General", "Advanced"};
    ImGui::SetCursorPos(ImVec2(sidebarW + 20, 12));
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
        ImGui::SameLine(0, 12);
    }
    
    // Обработка перетаскивания за таск-бар
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
    
    // Контент
    float contentStartX = sidebarW + 20;
    float contentStartY = topbarH + 20;
    float colWidth = (W - sidebarW - 40) * 0.5f;
    
    if (self.selectedSidebarTab == 0) { // Visuals
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        elem::simple_category("ESP Demo");
        elem::toggle("Box ESP", &g_esp_box, "Draws box around enemies");
        elem::toggle("Health Bar", &g_esp_health, "Shows health indicator");
        elem::toggle("Nickname", &g_esp_nickname, "Shows player names");
        elem::end_category();
    }
    else if (self.selectedSidebarTab == 1) { // Combat
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        elem::simple_category("Combat Settings");
        elem::toggle("Wallbang", &g_wallbang, "Shoot through walls");
        elem::toggle("NoRecoil", &g_norecoil, "Zero weapon recoil");
        elem::end_category();
    }
    else if (self.selectedSidebarTab == 3) { // Movement
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        elem::simple_category("Movement");
        elem::toggle("BunnyHop", &g_bunnyhop, "Auto jump on landing");
        elem::end_category();
    }
    else if (self.selectedSidebarTab == 4) { // Misc
        ImGui::SetCursorPos(ImVec2(contentStartX, contentStartY));
        elem::simple_category("Misc");
        elem::toggle("Offscreen", &g_esp_box, "Shows indicators out of view");
        elem::end_category();
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
