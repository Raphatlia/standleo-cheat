#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import "imgui.h"
#import "imgui_impl_metal.h"
#include "medium.hpp"

static bool g_wallbang = true;
static bool g_norecoil = true;
static bool g_bunnyhop = false;
static bool g_esp_box = true;
static bool g_esp_health = true;
static bool g_esp_nickname = true;

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
    
    // Создаём хост-вью для меню (420x360)
    self.hostView = [[CheatHostView alloc] initWithFrame:CGRectMake(10, 120, 420, 360)];
    self.hostView.backgroundColor = [UIColor clearColor];
    self.hostView.hidden = YES;
    self.hostView.userInteractionEnabled = NO;
    [keyWindow addSubview:self.hostView];
    
    // Metal инициализация
    self.device = MTLCreateSystemDefaultDevice();
    self.commandQueue = [self.device newCommandQueue];
    
    self.metalLayer = (CAMetalLayer *)self.hostView.layer;
    self.metalLayer.device = self.device;
    self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalLayer.framebufferOnly = NO;
    self.metalLayer.opaque = NO;
    self.metalLayer.backgroundColor = [UIColor clearColor].CGColor;
    self.metalLayer.contentsScale = scale;
    self.metalLayer.drawableSize = CGSizeMake(420 * scale, 360 * scale);
    
    // ImGui инициализация
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2(420, 360);
    io.DisplayFramebufferScale = ImVec2(scale, scale);
    io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange;
    
    // Загружаем шрифт Instrument Sans
    io.Fonts->AddFontFromMemoryTTF(
        instrument_sans_medium_ttf,
        sizeof(instrument_sans_medium_ttf),
        13.0f * 2.0f,
        nullptr,
        io.Fonts->GetGlyphRangesCyrillic()
    );
    io.FontGlobalScale = 0.5f;
    
    ImGui_ImplMetal_Init(self.device);
    
    // Стилизация (тёмная тема с фиолетовым акцентом)
    ImGuiStyle &style = ImGui::GetStyle();
    style.WindowRounding = 12.0f;
    style.ChildRounding = 10.0f;
    style.FrameRounding = 8.0f;
    style.TabRounding = 8.0f;
    style.WindowPadding = ImVec2(14, 14);
    style.ItemSpacing = ImVec2(10, 8);
    style.WindowBorderSize = 1.0f;
    style.ChildBorderSize = 0.0f;
    
    ImVec4 *colors = style.Colors;
    colors[ImGuiCol_Text] = ImVec4(0.92f, 0.92f, 0.96f, 1.0f);
    colors[ImGuiCol_TextDisabled] = ImVec4(0.42f, 0.42f, 0.52f, 1.0f);
    colors[ImGuiCol_WindowBg] = ImVec4(0.04f, 0.04f, 0.07f, 0.98f);
    colors[ImGuiCol_ChildBg] = ImVec4(0.0f, 0.0f, 0.0f, 0.0f);
    colors[ImGuiCol_Border] = ImVec4(0.12f, 0.12f, 0.18f, 1.0f);
    colors[ImGuiCol_CheckMark] = ImVec4(0.49f, 0.36f, 1.0f, 1.0f);
    colors[ImGuiCol_SliderGrab] = ImVec4(0.49f, 0.36f, 1.0f, 1.0f);
    colors[ImGuiCol_Separator] = ImVec4(0.15f, 0.15f, 0.22f, 1.0f);
    
    self.isReady = YES;
    
    // Кнопка переключения меню (⚡ в правом верхнем углу)
    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.frame = CGRectMake(screenSize.width - 80, 60, 60, 60);
    self.toggleButton.backgroundColor = [UIColor colorWithRed:0.49 green:0.36 blue:1.0 alpha:0.85];
    self.toggleButton.layer.cornerRadius = 30;
    self.toggleButton.layer.borderWidth = 2;
    self.toggleButton.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.toggleButton setTitle:@"⚡" forState:UIControlStateNormal];
    self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:26];
    [self.toggleButton addTarget:self action:@selector(toggleMenu:) forControlEvents:UIControlEventTouchUpInside];
    [keyWindow addSubview:self.toggleButton];
    
    // Запускаем рендер-цикл
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
    
    // Главное окно меню
    ImGui::SetNextWindowPos(ImVec2(0, 0), ImGuiCond_Always);
    ImGui::SetNextWindowSize(ImVec2(420, 360), ImGuiCond_Always);
    ImGui::Begin("##main_window", nullptr,
                 ImGuiWindowFlags_NoResize |
                 ImGuiWindowFlags_NoCollapse |
                 ImGuiWindowFlags_NoMove |
                 ImGuiWindowFlags_NoTitleBar);
    
    // Логотип в сайдбаре
    ImVec2 logoPos = ImGui::GetCursorScreenPos();
    ImGui::GetWindowDrawList()->AddCircleFilled(
        ImVec2(logoPos.x + 50, logoPos.y + 24),
        18,
        IM_COL32(124, 92, 255, 255)
    );
    ImGui::SetCursorScreenPos(ImVec2(logoPos.x + 44, logoPos.y + 14));
    ImGui::Text("A");
    ImGui::Spacing();
    ImGui::Spacing();
    
    // Сайдбар с вкладками
    const char *tabs[] = {"ESP", "Chams", "World", "Ragebot", "Misc", "Configs"};
    int tabCount = 6;
    
    for (int i = 0; i < tabCount; i++) {
        bool isSelected = (self.selectedTab == i);
        ImVec2 tabPos = ImGui::GetCursorScreenPos();
        
        // Подсветка активной вкладки
        if (isSelected) {
            ImGui::GetWindowDrawList()->AddRectFilled(
                tabPos,
                ImVec2(tabPos.x + 100, tabPos.y + 30),
                IM_COL32(28, 28, 44, 255),
                8.0f
            );
            ImGui::GetWindowDrawList()->AddRectFilled(
                ImVec2(tabPos.x, tabPos.y + 6),
                ImVec2(tabPos.x + 3, tabPos.y + 24),
                IM_COL32(124, 92, 255, 255),
                2.0f
            );
        }
        
        ImGui::SetCursorScreenPos(ImVec2(tabPos.x + 12, tabPos.y + 7));
        if (ImGui::Selectable(tabs[i], isSelected, 0, ImVec2(100, 30))) {
            self.selectedTab = i;
        }
        ImGui::Spacing();
    }
    
    ImGui::SameLine();
    
    // Контентная область
    ImGui::BeginGroup();
    
    if (self.selectedTab == 0) { // ESP
        // Карточка 1: ESP Demo
        ImVec2 card1Pos = ImGui::GetCursorScreenPos();
        float card1Width = 200;
        float card1Height = 150;
        
        ImGui::GetWindowDrawList()->AddRectFilled(
            card1Pos,
            ImVec2(card1Pos.x + card1Width, card1Pos.y + card1Height),
            IM_COL32(16, 16, 26, 255),
            10.0f
        );
        ImGui::GetWindowDrawList()->AddRect(
            card1Pos,
            ImVec2(card1Pos.x + card1Width, card1Pos.y + card1Height),
            IM_COL32(30, 30, 46, 255),
            10.0f,
            0,
            1.0f
        );
        
        ImGui::SetCursorScreenPos(ImVec2(card1Pos.x + 12, card1Pos.y + 10));
        ImGui::TextColored(ImVec4(0.85f, 0.85f, 0.92f, 1.0f), "ESP Demo");
        ImGui::SetCursorScreenPos(ImVec2(card1Pos.x + 12, card1Pos.y + 34));
        
        // Toggle: Offscreen
        ImVec2 togglePos = ImGui::GetCursorScreenPos();
        float toggleWidth = card1Width - 24;
        ImGui::GetWindowDrawList()->AddRectFilled(
            togglePos,
            ImVec2(togglePos.x + toggleWidth, togglePos.y + 36),
            IM_COL32(18, 18, 26, 255),
            8.0f
        );
        ImGui::SetCursorScreenPos(ImVec2(togglePos.x + 12, togglePos.y + 10));
        ImGui::Text("Offscreen");
        ImGui::SetCursorScreenPos(ImVec2(togglePos.x + 12, togglePos.y + 24));
        ImGui::TextDisabled("Shows enemies that are out of visibility");
        
        float tx = togglePos.x + toggleWidth - 44;
        float ty = togglePos.y + 10;
        ImDrawList *dl = ImGui::GetWindowDrawList();
        dl->AddRectFilled(
            ImVec2(tx, ty),
            ImVec2(tx + 36, ty + 18),
            g_esp_box ? IM_COL32(124, 92, 255, 255) : IM_COL32(40, 40, 55, 255),
            9.0f
        );
        dl->AddCircleFilled(
            ImVec2(g_esp_box ? tx + 27 : tx + 9, ty + 9),
            7.0f,
            IM_COL32(255, 255, 255, 255)
        );
        
        ImGui::SetCursorScreenPos(togglePos);
        if (ImGui::InvisibleButton("##esp_offscreen", ImVec2(toggleWidth, 36))) {
            g_esp_box = !g_esp_box;
        }
        ImGui::Spacing();
        
        ImGui::SetCursorScreenPos(ImVec2(card1Pos.x, card1Pos.y + card1Height + 8));
        
        // Карточка 2: Preview
        ImGui::SameLine();
        ImVec2 card2Pos = ImGui::GetCursorScreenPos();
        float card2Width = 180;
        float card2Height = 150;
        
        ImGui::GetWindowDrawList()->AddRectFilled(
            card2Pos,
            ImVec2(card2Pos.x + card2Width, card2Pos.y + card2Height),
            IM_COL32(16, 16, 26, 255),
            10.0f
        );
        ImGui::GetWindowDrawList()->AddRect(
            card2Pos,
            ImVec2(card2Pos.x + card2Width, card2Pos.y + card2Height),
            IM_COL32(30, 30, 46, 255),
            10.0f,
            0,
            1.0f
        );
        
        ImGui::SetCursorScreenPos(ImVec2(card2Pos.x + 12, card2Pos.y + 10));
        ImGui::TextColored(ImVec4(0.85f, 0.85f, 0.92f, 1.0f), "Preview");
        ImGui::SetCursorScreenPos(ImVec2(card2Pos.x + 12, card2Pos.y + 34));
        ImGui::TextDisabled("ESP preview placeholder");
        ImGui::SetCursorScreenPos(ImVec2(card2Pos.x, card2Pos.y + card2Height + 8));
    }
    else if (self.selectedTab == 4) { // Misc
        ImVec2 cardPos = ImGui::GetCursorScreenPos();
        float cardWidth = 280;
        float cardHeight = 150;
        
        ImGui::GetWindowDrawList()->AddRectFilled(
            cardPos,
            ImVec2(cardPos.x + cardWidth, cardPos.y + cardHeight),
            IM_COL32(16, 16, 26, 255),
            10.0f
        );
        ImGui::GetWindowDrawList()->AddRect(
            cardPos,
            ImVec2(cardPos.x + cardWidth, cardPos.y + cardHeight),
            IM_COL32(30, 30, 46, 255),
            10.0f,
            0,
            1.0f
        );
        
        ImGui::SetCursorScreenPos(ImVec2(cardPos.x + 12, cardPos.y + 10));
        ImGui::TextColored(ImVec4(0.85f, 0.85f, 0.92f, 1.0f), "Combat & Movement");
        ImGui::SetCursorScreenPos(ImVec2(cardPos.x + 12, cardPos.y + 34));
        
        // Toggle: Wallbang
        ImVec2 togglePos = ImGui::GetCursorScreenPos();
        float toggleWidth = cardWidth - 24;
        ImGui::GetWindowDrawList()->AddRectFilled(
            togglePos,
            ImVec2(togglePos.x + toggleWidth, togglePos.y + 36),
            IM_COL32(18, 18, 26, 255),
            8.0f
        );
        ImGui::SetCursorScreenPos(ImVec2(togglePos.x + 12, togglePos.y + 10));
        ImGui::Text("Wallbang");
        ImGui::SetCursorScreenPos(ImVec2(togglePos.x + 12, togglePos.y + 24));
        ImGui::TextDisabled("Shoot through walls");
        
        float tx = togglePos.x + toggleWidth - 44;
        float ty = togglePos.y + 10;
        ImDrawList *dl = ImGui::GetWindowDrawList();
        dl->AddRectFilled(
            ImVec2(tx, ty),
            ImVec2(tx + 36, ty + 18),
            g_wallbang ? IM_COL32(124, 92, 255, 255) : IM_COL32(40, 40, 55, 255),
            9.0f
        );
        dl->AddCircleFilled(
            ImVec2(g_wallbang ? tx + 27 : tx + 9, ty + 9),
            7.0f,
            IM_COL32(255, 255, 255, 255)
        );
        
        ImGui::SetCursorScreenPos(togglePos);
        if (ImGui::InvisibleButton("##wallbang", ImVec2(toggleWidth, 36))) {
            g_wallbang = !g_wallbang;
        }
        ImGui::Spacing();
        
        // Toggle: NoRecoil
        togglePos = ImGui::GetCursorScreenPos();
        ImGui::GetWindowDrawList()->AddRectFilled(
            togglePos,
            ImVec2(togglePos.x + toggleWidth, togglePos.y + 36),
            IM_COL32(18, 18, 26, 255),
            8.0f
        );
        ImGui::SetCursorScreenPos(ImVec2(togglePos.x + 12, togglePos.y + 10));
        ImGui::Text("NoRecoil");
        ImGui::SetCursorScreenPos(ImVec2(togglePos.x + 12, togglePos.y + 24));
        ImGui::TextDisabled("Zero recoil");
        
        tx = togglePos.x + toggleWidth - 44;
        ty = togglePos.y + 10;
        dl = ImGui::GetWindowDrawList();
        dl->AddRectFilled(
            ImVec2(tx, ty),
            ImVec2(tx + 36, ty + 18),
            g_norecoil ? IM_COL32(124, 92, 255, 255) : IM_COL32(40, 40, 55, 255),
            9.0f
        );
        dl->AddCircleFilled(
            ImVec2(g_norecoil ? tx + 27 : tx + 9, ty + 9),
            7.0f,
            IM_COL32(255, 255, 255, 255)
        );
        
        ImGui::SetCursorScreenPos(togglePos);
        if (ImGui::InvisibleButton("##norecoil", ImVec2(toggleWidth, 36))) {
            g_norecoil = !g_norecoil;
        }
        ImGui::Spacing();
        
        // Toggle: BunnyHop
        togglePos = ImGui::GetCursorScreenPos();
        ImGui::GetWindowDrawList()->AddRectFilled(
            togglePos,
            ImVec2(togglePos.x + toggleWidth, togglePos.y + 36),
            IM_COL32(18, 18, 26, 255),
            8.0f
        );
        ImGui::SetCursorScreenPos(ImVec2(togglePos.x + 12, togglePos.y + 10));
        ImGui::Text("BunnyHop");
        ImGui::SetCursorScreenPos(ImVec2(togglePos.x + 12, togglePos.y + 24));
        ImGui::TextDisabled("Auto jump");
        
        tx = togglePos.x + toggleWidth - 44;
        ty = togglePos.y + 10;
        dl = ImGui::GetWindowDrawList();
        dl->AddRectFilled(
            ImVec2(tx, ty),
            ImVec2(tx + 36, ty + 18),
            g_bunnyhop ? IM_COL32(124, 92, 255, 255) : IM_COL32(40, 40, 55, 255),
            9.0f
        );
        dl->AddCircleFilled(
            ImVec2(g_bunnyhop ? tx + 27 : tx + 9, ty + 9),
            7.0f,
            IM_COL32(255, 255, 255, 255)
        );
        
        ImGui::SetCursorScreenPos(togglePos);
        if (ImGui::InvisibleButton("##bunnyhop", ImVec2(toggleWidth, 36))) {
            g_bunnyhop = !g_bunnyhop;
        }
        
        ImGui::SetCursorScreenPos(ImVec2(cardPos.x, cardPos.y + cardHeight + 8));
    }
    else {
        ImGui::TextDisabled("%s: coming soon", tabs[self.selectedTab]);
    }
    
    ImGui::EndGroup();
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
