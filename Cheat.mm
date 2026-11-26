#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include "imgui.h"
#include "imgui_internal.h"
#include "imgui_impl_metal.h"

#include "font.hpp"
#include "logo.hpp"

#include <vector>
#include <string>
#include <unordered_map>
#include <cmath>
#include <cstdio>

// === Состояния (готово к хукам) ===
static bool g_wallbang = true;
static bool g_norecoil = true;
static bool g_bunnyhop = false;
static bool g_esp_box = true;
static bool g_esp_health = true;
static bool g_esp_nickname = true;
static bool g_offscreen = false;
static bool g_internal = false;

static float g_slider = 0.0f;
static int   g_combo = 0;
static ImVec4 g_col1 = ImVec4(0, 1, 0, 1);
static ImVec4 g_col2 = ImVec4(1, 0, 0, 1);

// === Вспомогательные ===
static ImVec4 lerp4(ImVec4 a, ImVec4 b, float t) {
    return ImVec4(a.x+(b.x-a.x)*t, a.y+(b.y-a.y)*t, a.z+(b.z-a.z)*t, a.w+(b.w-a.w)*t);
}
static float anim_f(ImGuiID id, float target, float speed = 12.0f) {
    static std::unordered_map<ImGuiID, float> m;
    float& cur = m[id];
    float t = ImClamp(ImGui::GetIO().DeltaTime * speed, 0.0f, 1.0f);
    cur += (target - cur) * t;
    if (fabsf(cur - target) < 0.0005f) cur = target;
    return cur;
}
static ImVec4 anim_v(ImGuiID id, ImVec4 target, float speed = 12.0f) {
    static std::unordered_map<ImGuiID, ImVec4> m;
    ImVec4& cur = m[id];
    float t = ImClamp(ImGui::GetIO().DeltaTime * speed, 0.0f, 1.0f);
    cur.x += (target.x - cur.x) * t;
    cur.y += (target.y - cur.y) * t;
    cur.z += (target.z - cur.z) * t;
    cur.w += (target.w - cur.w) * t;
    return cur;
}

#pragma mark - Логотип (векторный, обрезается сверху через foreground)
static void DrawLogoVector(ImDrawList* draw, ImVec2 center, float size) {
    float s = size;
    draw->AddCircleFilled(center, s * 1.2f, IM_COL32(234, 193, 251, 40));
    ImVec2 p1(center.x - s*0.3f, center.y - s*0.55f);
    ImVec2 p2(center.x + s*0.3f, center.y - s*0.55f);
    ImVec2 p3(center.x + s*0.7f, center.y + s*0.55f);
    ImVec2 p4(center.x - s*0.7f, center.y + s*0.55f);
    draw->AddQuadFilled(p1, p2, p3, p4, IM_COL32(238, 238, 244, 255));
    ImU32 bg = IM_COL32(15, 14, 24, 255);
    draw->AddTriangleFilled(ImVec2(center.x-s*0.7f, center.y-s*0.1f), ImVec2(center.x-s*0.4f, center.y+s*0.1f), ImVec2(center.x-s*0.7f, center.y+s*0.25f), bg);
    draw->AddTriangleFilled(ImVec2(center.x+s*0.7f, center.y-s*0.1f), ImVec2(center.x+s*0.4f, center.y+s*0.1f), ImVec2(center.x+s*0.7f, center.y+s*0.25f), bg);
    draw->AddTriangleFilled(ImVec2(center.x, center.y+s*0.05f), ImVec2(center.x-s*0.25f, center.y+s*0.55f), ImVec2(center.x+s*0.25f, center.y+s*0.55f), bg);
    draw->AddCircleFilled(ImVec2(center.x, center.y-s*0.15f), s*0.08f, bg);
}

#pragma mark - Toggle (как internal_toggle + описание)
static void custom_toggle(const char* label, bool* v, const char* description = nullptr) {
    ImGuiWindow* window = ImGui::GetCurrentWindow();
    if (window->SkipItems) return;
    const ImGuiID id = window->GetID(label);
    const ImVec2 label_size = ImGui::CalcTextSize(label);
    const float square_sz = ImGui::GetFrameHeight();
    const ImVec2 pos = window->DC.CursorPos;
    const float w = ImGui::GetContentRegionAvail().x;
    const ImRect total_bb(pos, pos + ImVec2(w, label_size.y + 14.0f));
    ImGui::ItemSize(total_bb, 4.0f);
    if (!ImGui::ItemAdd(total_bb, id)) return;

    bool hovered, held;
    bool pressed = ImGui::ButtonBehavior(total_bb, id, &hovered, &held);
    if (pressed) *v = !(*v);

    // Трек прижат к правому краю (как в оригинале)
    const ImRect check_bb(total_bb.Max.x - square_sz*2 + 10, total_bb.Min.y + 2, total_bb.Max.x, total_bb.Max.y - 2);

    float st = anim_f(id, *v ? 1.0f : 0.0f);
    ImVec4 outline = lerp4(ImVec4(55/255.f,55/255.f,66/255.f,1), ImVec4(1,1,1,1), st);
    ImVec4 pill    = lerp4(ImVec4(55/255.f,55/255.f,66/255.f,1), ImVec4(0,0,0,1), st);
    ImVec4 text    = anim_v(id+1, (*v || hovered) ? ImVec4(1,1,1,1) : ImVec4(155/255.f,155/255.f,155/255.f,1));

    ImDrawList* d = window->DrawList;
    int vs = d->VtxBuffer.Size;
    d->AddRectFilled(check_bb.Min, check_bb.Max, IM_COL32(25,25,25,(int)(st*255)), 666);
    int ve = d->VtxBuffer.Size;
    if (ve > vs)
        ImGui::ShadeVertsLinearColorGradientKeepAlpha(d, vs, ve, check_bb.Min, check_bb.Max,
            IM_COL32(218,221,216,255), IM_COL32(234,193,251,255));
    d->AddRect(check_bb.Min, check_bb.Max, ImGui::ColorConvertFloat4ToU32(outline), 666);
    float knobX = check_bb.Min.x + 8 + 14*st;
    d->AddCircleFilled(ImVec2(knobX, check_bb.GetCenter().y), 5.0f, ImGui::ColorConvertFloat4ToU32(pill), 200);
    d->AddText(total_bb.Min, ImGui::ColorConvertFloat4ToU32(text), label);

    if (description) {
        ImGui::SetCursorPosX(0);
        ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(155/255.f,155/255.f,155/255.f,1));
        ImGui::TextWrapped("%s", description);
        ImGui::PopStyleColor();
    }
}

#pragma mark - Slider (плавный градиент, как slider_scalar)
static void custom_slider(const char* label, float* v, float vmin, float vmax, const char* fmt = "%.0f") {
    ImGuiWindow* window = ImGui::GetCurrentWindow();
    if (window->SkipItems) return;
    const ImGuiID id = window->GetID(label);
    const ImVec2 label_size = ImGui::CalcTextSize(label);
    const float w = ImGui::GetContentRegionAvail().x;
    const ImVec2 pos = window->DC.CursorPos;
    const ImRect frame_bb(pos + ImVec2(0, label_size.y + 4), pos + ImVec2(w, label_size.y + 4 + 12));
    const ImRect total_bb(pos, frame_bb.Max + ImVec2(0, 4));
    ImGui::ItemSize(total_bb, 4.0f);
    if (!ImGui::ItemAdd(total_bb, id, &frame_bb)) return;

    // Версия-безопасный hover (без window->DC.ItemFlags!)
    bool hovered = ImGui::IsMouseHoveringRect(total_bb.Min, total_bb.Max);

    ImRect grab_bb;
    bool changed = ImGui::SliderBehavior(total_bb, id, ImGuiDataType_Float, v, &vmin, &vmax, fmt, ImGuiSliderFlags_None, &grab_bb);

    float grab = anim_f(id+2, grab_bb.Max.x - frame_bb.Min.x, 18.0f);
    ImVec4 text = anim_v(id+3, (ImGui::IsItemActive() || hovered || changed) ? ImVec4(1,1,1,1) : ImVec4(155/255.f,155/255.f,155/255.f,1));

    ImDrawList* d = window->DrawList;
    d->AddRect(frame_bb.Min + ImVec2(0,2), frame_bb.Max - ImVec2(0,2), IM_COL32(55,55,66,255), 12);
    int vs = d->VtxBuffer.Size;
    d->AddRectFilled(frame_bb.Min, ImVec2(frame_bb.Min.x + grab, frame_bb.Max.y), IM_COL32(25,25,25,255), 12);
    int ve = d->VtxBuffer.Size;
    if (ve > vs)
        ImGui::ShadeVertsLinearColorGradientKeepAlpha(d, vs, ve, frame_bb.Min, ImVec2(frame_bb.Min.x + grab, frame_bb.Max.y),
            IM_COL32(218,221,216,255), IM_COL32(234,193,251,255));
    d->AddCircleFilled(ImVec2(frame_bb.Min.x + grab, frame_bb.GetCenter().y), 6.0f, IM_COL32(255,255,255,255), 200);
    d->AddCircle(ImVec2(frame_bb.Min.x + grab, frame_bb.GetCenter().y), 6.0f, IM_COL32(0,0,0,80), 200, 1.0f);

    char buf[64]; snprintf(buf, sizeof(buf), fmt, *v);
    ImVec2 sep_sz = ImGui::CalcTextSize(">>");
    d->AddText(total_bb.Min + ImVec2(label_size.x + 5, 0), IM_COL32(65,65,65,255), ">>");
    d->AddText(total_bb.Min + ImVec2(label_size.x + 5 + sep_sz.x + 5, 0), IM_COL32(155,155,155,255), buf);
    d->AddText(total_bb.Min, ImGui::ColorConvertFloat4ToU32(text), label);
}

#pragma mark - Combo (с анимацией popup, стрелка треугольником)
static void custom_combo(const char* label, int* value, const char* items[], int count) {
    ImGuiWindow* window = ImGui::GetCurrentWindow();
    if (window->SkipItems) return;
    const ImGuiID id = window->GetID(label);
    const ImVec2 label_size = ImGui::CalcTextSize(label);
    const float w = ImGui::GetContentRegionAvail().x;
    const ImVec2 pos = window->DC.CursorPos;
    const ImRect box(pos + ImVec2(0, label_size.y + 4), pos + ImVec2(w, label_size.y + 4 + 26));
    const ImRect total_bb(pos, box.Max);
    ImGui::ItemSize(total_bb, 4.0f);
    if (!ImGui::ItemAdd(total_bb, id)) return;

    bool hovered, held;
    bool pressed = ImGui::ButtonBehavior(total_bb, id, &hovered, &held);
    if (pressed) ImGui::OpenPopup("##combo_popup");

    bool open = ImGui::IsPopupOpen("##combo_popup");
    ImVec4 text = anim_v(id+4, (hovered || open) ? ImVec4(1,1,1,1) : ImVec4(155/255.f,155/255.f,155/255.f,1));
    ImDrawList* d = window->DrawList;
    d->AddRect(box.Min, box.Max, IM_COL32(55,55,66,255), 6);
    d->AddText(total_bb.Min, ImGui::ColorConvertFloat4ToU32(text), label);
    d->AddText(box.Min + ImVec2(8, 6), ImGui::ColorConvertFloat4ToU32(text), items[*value]);
    ImVec2 ar(box.Max.x - 14, box.Min.y + 10);
    d->AddTriangleFilled(ar, ImVec2(ar.x+8, ar.y), ImVec2(ar.x+4, ar.y+6), ImGui::ColorConvertFloat4ToU32(text));

    ImGui::SetNextWindowSize(ImVec2(box.GetWidth(), 0));
    if (ImGui::BeginPopup("##combo_popup")) {
        float a = anim_f(id+5, 1.0f, 16.0f);
        ImGui::PushStyleVar(ImGuiStyleVar_Alpha, a);
        ImGui::PushStyleColor(ImGuiCol_PopupBg, ImVec4(10/255.f,14/255.f,21/255.f,1));
        for (int i = 0; i < count; i++) {
            bool sel = (i == *value);
            if (ImGui::Selectable(items[i], sel)) { *value = i; ImGui::CloseCurrentPopup(); }
        }
        ImGui::PopStyleColor();
        ImGui::PopStyleVar();
        ImGui::EndPopup();
    } else {
        anim_f(id+5, 0.0f, 16.0f);
    }
}

#pragma mark - Colorpicker (два квадратика + popup)
static void custom_color(const char* label, ImVec4* colors, int count) {
    ImGuiWindow* window = ImGui::GetCurrentWindow();
    if (window->SkipItems) return;
    const ImGuiID id = window->GetID(label);   // ← исправлено: было window::GetID
    const ImVec2 label_size = ImGui::CalcTextSize(label);
    const float w = ImGui::GetContentRegionAvail().x;
    const float sz = ImGui::GetFrameHeight();
    const ImVec2 pos = window->DC.CursorPos;
    const ImRect total_bb(pos, pos + ImVec2(w, label_size.y + 8));
    ImGui::ItemSize(total_bb, 4.0f);
    if (!ImGui::ItemAdd(total_bb, id)) return;

    ImDrawList* d = window->DrawList;
    d->AddText(total_bb.Min, IM_COL32(155,155,155,255), label);
    for (int i = 0; i < count; i++) {
        float x1 = total_bb.Max.x - sz - 8 - (sz+8)*i;
        ImRect cb(ImVec2(x1, total_bb.Min.y), ImVec2(x1+sz, total_bb.Min.y+sz));
        ImGuiID cid = id * 10 + i + 1;
        ImGui::ItemAdd(cb, cid);
        bool h2, hd; bool p2 = ImGui::ButtonBehavior(cb, cid, &h2, &hd);
        if (p2) ImGui::OpenPopup("##color_popup");
        d->AddRectFilled(cb.Min, cb.Max, ImGui::ColorConvertFloat4ToU32(colors[i]), 3);
        d->AddRect(cb.Min, cb.Max, IM_COL32(55,55,66,255), 3);
    }
    if (ImGui::BeginPopup("##color_popup")) {
        float a = anim_f(id+6, 1.0f, 16.0f);
        ImGui::PushStyleVar(ImGuiStyleVar_Alpha, a);
        ImGui::ColorPicker4("##p", (float*)&colors[0], ImGuiColorEditFlags_NoInputs | ImGuiColorEditFlags_NoLabel);
        ImGui::PopStyleVar();
        ImGui::EndPopup();
    } else { anim_f(id+6, 0.0f, 16.0f); }
}

#pragma mark - Category (карточка как simple_category)
static void begin_category(const char* title, float w, float h) {
    ImVec2 pos = ImGui::GetCursorScreenPos();
    ImDrawList* d = ImGui::GetWindowDrawList();
    d->AddRect(pos, ImVec2(pos.x+w, pos.y+h), IM_COL32(41,43,55,255), 5, 0, 1);
    ImGui::BeginGroup();
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(155/255.f,155/255.f,155/255.f,1));
    ImGui::SetCursorPosX(10);
    ImGui::Text("%s", title);
    ImGui::PopStyleColor();
    ImGui::SetCursorPosX(0);
    ImVec2 lp = ImGui::GetCursorScreenPos();
    d->AddLine(lp, ImVec2(lp.x+w, lp.y), IM_COL32(41,43,55,255), 1);
    ImGui::Dummy(ImVec2(0,4));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(10,8));
    ImGui::BeginChild(title, ImVec2(w, h-30), false, ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
    ImGui::SetCursorPosX(0);
}
static void end_category() {
    ImGui::EndChild();
    ImGui::PopStyleVar();
    ImGui::EndGroup();
}

#pragma mark - Metal Host View
@interface UIOverlayHostView : UIView
@end
@implementation UIOverlayHostView
+ (Class)layerClass { return [CAMetalLayer class]; }
- (void)touchesBegan:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e {
    CGPoint p = [[t anyObject] locationInView:self];
    ImGui::GetIO().MousePos = ImVec2(p.x, p.y); ImGui::GetIO().MouseDown[0] = true;
}
- (void)touchesMoved:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e {
    CGPoint p = [[t anyObject] locationInView:self];
    ImGui::GetIO().MousePos = ImVec2(p.x, p.y);
}
- (void)touchesEnded:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e { ImGui::GetIO().MouseDown[0] = false; }
- (void)touchesCancelled:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e { ImGui::GetIO().MouseDown[0] = false; }
@end

#pragma mark - Manager
@interface AntisocialGUIManager : NSObject
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) UIOverlayHostView *hostView;
@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) BOOL isReady, isMenuVisible, isDragging;
@property (nonatomic, assign) int selectedSidebarTab, selectedTopTab;
@property (nonatomic, assign) CGPoint menuOffset, dragStartPos;
@property (nonatomic, assign) ImFont* mainFont;
@property (nonatomic, assign) ImFont* logoFont;
@end

@implementation AntisocialGUIManager
static AntisocialGUIManager *sharedInstance = nil;
+ (AntisocialGUIManager*)shared { if(!sharedInstance) sharedInstance=[[self alloc] init]; return sharedInstance; }
+ (void)load {
    for (int i=1;i<=15;i++)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(i*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [[AntisocialGUIManager shared] trySetup]; });
}
- (UIWindow*)findKeyWindow {
    for (UIScene* s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow* w in ((UIWindowScene*)s).windows) if (w.isKeyWindow) return w;
    } return nil;
}
- (void)trySetup {
    if (self.hostView) return;
    UIWindow* kw = [self findKeyWindow]; if(!kw) return;
    CGFloat scale = [UIScreen mainScreen].scale;
    CGSize sc = kw.bounds.size;
    CGFloat W=540, H=380;
    CGFloat px=(sc.width-W)*0.5, py=(sc.height-H)*0.5;
    self.menuOffset=CGPointMake(px,py);
    self.hostView=[[UIOverlayHostView alloc] initWithFrame:CGRectMake(px,py,W,H)];
    self.hostView.backgroundColor=[UIColor clearColor]; self.hostView.hidden=YES; self.hostView.userInteractionEnabled=NO;
    [kw addSubview:self.hostView];
    self.device=MTLCreateSystemDefaultDevice(); self.commandQueue=[self.device newCommandQueue];
    self.metalLayer=(CAMetalLayer*)self.hostView.layer;
    self.metalLayer.device=self.device; self.metalLayer.pixelFormat=MTLPixelFormatBGRA8Unorm;
    self.metalLayer.framebufferOnly=NO; self.metalLayer.opaque=NO;
    self.metalLayer.backgroundColor=[UIColor clearColor].CGColor; self.metalLayer.contentsScale=scale;
    self.metalLayer.drawableSize=CGSizeMake(W*scale,H*scale);
    ImGui::CreateContext(); ImGuiIO& io=ImGui::GetIO();
    io.DisplaySize=ImVec2(W,H); io.DisplayFramebufferScale=ImVec2(scale,scale);
    io.ConfigFlags|=ImGuiConfigFlags_NoMouseCursorChange;
    ImFontConfig fc; fc.FontDataOwnedByAtlas=false;
    self.mainFont=io.Fonts->AddFontFromMemoryTTF((void*)font_medium,sizeof(font_medium),13.0f*scale,&fc,io.Fonts->GetGlyphRangesCyrillic());
    ImFontConfig lc; lc.FontDataOwnedByAtlas=false;
    self.logoFont=io.Fonts->AddFontFromMemoryTTF((void*)logo_ttf,sizeof(logo_ttf),40.0f*scale,&lc);
    io.FontGlobalScale=1.0f/scale;
    ImGui_ImplMetal_Init(self.device);
    self.selectedSidebarTab=0; self.selectedTopTab=0; self.isReady=YES;
    CGFloat bs=44; self.toggleButton=[UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.frame=CGRectMake(sc.width-60,40,bs,bs);
    self.toggleButton.backgroundColor=[UIColor colorWithRed:0.15 green:0.12 blue:0.25 alpha:0.9];
    self.toggleButton.layer.cornerRadius=22; self.toggleButton.layer.borderWidth=1;
    self.toggleButton.layer.borderColor=[UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
    [self.toggleButton setTitle:@"S" forState:UIControlStateNormal];
    [self.toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleButton.titleLabel.font=[UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    [self.toggleButton addTarget:self action:@selector(toggleMenu:) forControlEvents:UIControlEventTouchUpInside];
    [kw addSubview:self.toggleButton];
    self.displayLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(render)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
- (void)toggleMenu:(UIButton*)b {
    self.isMenuVisible=!self.isMenuVisible; self.hostView.hidden=!self.isMenuVisible;
    self.hostView.userInteractionEnabled=self.isMenuVisible;
    if(!self.isMenuVisible){ImGui::GetIO().MouseDown[0]=false;ImGui::GetIO().MousePos=ImVec2(-FLT_MAX,-FLT_MAX);}
}
- (void)render {
    if(!self.isReady||!self.isMenuVisible) return;
    id<CAMetalDrawable> dr=[self.metalLayer nextDrawable]; if(!dr) return;
    MTLRenderPassDescriptor* rp=[MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture=dr.texture; rp.colorAttachments[0].loadAction=MTLLoadActionClear;
    rp.colorAttachments[0].storeAction=MTLStoreActionStore; rp.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);
    ImGui_ImplMetal_NewFrame(rp); ImGui::NewFrame();

    const float W=540,H=380,sidebarW=130,topbarH=36;
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding,ImVec2(0,0));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding,10.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize,1.0f);
    ImGui::PushStyleColor(ImGuiCol_WindowBg,ImVec4(0.055f,0.055f,0.085f,0.98f));
    ImGui::PushStyleColor(ImGuiCol_Border,ImVec4(1,1,1,0.08f));
    ImGui::SetNextWindowPos(ImVec2(0,0),ImGuiCond_Always);
    ImGui::SetNextWindowSize(ImVec2(W,H),ImGuiCond_Always);
    ImGui::Begin("##main_ui",nullptr,ImGuiWindowFlags_NoResize|ImGuiWindowFlags_NoCollapse|ImGuiWindowFlags_NoTitleBar|ImGuiWindowFlags_NoScrollbar|ImGuiWindowFlags_NoScrollWithMouse);
    ImDrawList* d=ImGui::GetWindowDrawList(); ImVec2 wp=ImGui::GetWindowPos();

    d->AddRectFilled(wp,ImVec2(wp.x+sidebarW,wp.y+H),IM_COL32(12,12,18,255),10,ImDrawFlags_RoundCornersLeft);
    d->AddLine(ImVec2(wp.x+sidebarW,wp.y),ImVec2(wp.x+sidebarW,wp.y+H),IM_COL32(255,255,255,16),1);
    d->AddLine(ImVec2(wp.x+sidebarW,wp.y+topbarH),ImVec2(wp.x+W,wp.y+topbarH),IM_COL32(255,255,255,16),1);

    if(self.logoFont){
        ImDrawList* fg=ImGui::GetForegroundDrawList();
        ImGui::PushFont(self.logoFont);
        ImVec2 gs=ImGui::CalcTextSize("A");
        fg->AddText(ImVec2(wp.x+sidebarW*0.5f-gs.x*0.5f, wp.y-10.0f),IM_COL32(238,238,244,255),"A");
        ImGui::PopFont();
    }

    const char* side[]={"Visuals","Combat","World","Movement","Misc","Configs"};
    ImGui::SetCursorPos(ImVec2(8,52));
    ImGui::PushStyleVar(ImGuiStyleVar_ButtonTextAlign,ImVec2(0,0.5f));
    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding,ImVec2(10,0));
    ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding,6);
    for(int i=0;i<6;i++){
        bool active=(self.selectedSidebarTab==i);
        ImGui::SetCursorPosX(8);
        ImGuiID bid=ImGui::GetID(side[i]);
        ImVec2 cp=ImGui::GetCursorScreenPos();
        float hov=anim_f(bid+100, ImGui::IsMouseHoveringRect(cp,cp+ImVec2(sidebarW-16,30))?1.0f:0.0f, 14);
        ImVec4 bg=lerp4(ImVec4(0,0,0,0), ImVec4(0.15f,0.12f,0.25f,1), active?1.0f:hov*0.6f);
        ImGui::PushStyleColor(ImGuiCol_Button,bg);
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered,bg);
        ImGui::PushStyleColor(ImGuiCol_ButtonActive,bg);
        ImGui::PushStyleColor(ImGuiCol_Text, active?ImVec4(0.95f,0.95f,0.98f,1):ImVec4(0.55f,0.55f,0.62f,1));
        if(ImGui::Button(side[i],ImVec2(sidebarW-16,30))) self.selectedSidebarTab=i;
        ImGui::PopStyleColor(4);
        ImGui::Dummy(ImVec2(0,3));
    }
    ImGui::PopStyleVar(3);

    ImVec2 pp(wp.x+10,wp.y+H-34);
    d->AddCircle(ImVec2(pp.x+8,pp.y+8),7,IM_COL32(255,255,255,200),0,1.5f);
    d->AddText(ImVec2(pp.x+20,pp.y+2),IM_COL32(235,235,242,255),"@STANDLEO");
    d->AddText(ImVec2(pp.x+20,pp.y+16),IM_COL32(255,215,0,255),"Premium");

    const char* top[]={"General","Advanced"};
    ImGui::SetCursorPos(ImVec2(sidebarW+16,8));
    for(int i=0;i<2;i++){
        bool active=(self.selectedTopTab==i);
        ImGui::PushStyleColor(ImGuiCol_Button,ImVec4(0,0,0,0));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered,ImVec4(0,0,0,0));
        ImGui::PushStyleColor(ImGuiCol_ButtonActive,ImVec4(0,0,0,0));
        ImGui::PushStyleColor(ImGuiCol_Text, active?ImVec4(0.95f,0.95f,0.98f,1):ImVec4(0.5f,0.5f,0.58f,1));
        if(ImGui::Button(top[i],ImVec2(72,22))) self.selectedTopTab=i;
        ImGui::PopStyleColor(4); ImGui::SameLine(0,8);
    }

    ImVec2 mp=ImGui::GetIO().MousePos;
    bool inBar=(mp.x>=sidebarW&&mp.x<=W&&mp.y>=0&&mp.y<=topbarH);
    if(inBar&&ImGui::IsMouseClicked(0)){self.isDragging=YES;self.dragStartPos=CGPointMake(mp.x-self.menuOffset.x,mp.y-self.menuOffset.y);}
    if(self.isDragging&&ImGui::IsMouseDown(0)){
        CGPoint no=CGPointMake(mp.x-self.dragStartPos.x,mp.y-self.dragStartPos.y);
        self.menuOffset=no; self.hostView.frame=CGRectMake(no.x,no.y,W,H);
    } else if(!ImGui::IsMouseDown(0)) self.isDragging=NO;

    float cx=sidebarW+16, cy=topbarH+12, colW=(W-sidebarW-32)*0.5f;
    if(self.selectedSidebarTab==0){
        ImGui::SetCursorPos(ImVec2(cx,cy)); begin_category("Visuals",colW,230);
        custom_toggle("Box ESP",&g_esp_box);
        custom_toggle("Health Bar",&g_esp_health);
        custom_toggle("Nickname",&g_esp_nickname);
        end_category();
        ImGui::SetCursorPos(ImVec2(cx+colW+12,cy)); begin_category("Settings",colW,230);
        custom_toggle("Offscreen",&g_offscreen,"With configuration!");
        custom_toggle("Internal too?",&g_internal);
        end_category();
    } else if(self.selectedSidebarTab==1){
        ImGui::SetCursorPos(ImVec2(cx,cy)); begin_category("Combat",colW,230);
        custom_toggle("Wallbang",&g_wallbang);
        custom_toggle("NoRecoil",&g_norecoil);
        end_category();
        ImGui::SetCursorPos(ImVec2(cx+colW+12,cy)); begin_category("Category example",colW,230);
        custom_toggle("Simple switch",&g_esp_box);
        custom_toggle("Another toggle",&g_esp_health,"Lorem ipsum paster sin shluxi");
        end_category();
    } else if(self.selectedSidebarTab==2){
        ImGui::SetCursorPos(ImVec2(cx,cy)); begin_category("World",colW*2+12,230);
        custom_slider("And slider??",&g_slider,0,100,"%.0f");
        ImGui::Dummy(ImVec2(0,6));
        ImVec4 cols[2]={g_col1,g_col2};
        custom_color("Colorpicker",cols,2);
        g_col1=cols[0]; g_col2=cols[1];
        end_category();
    } else if(self.selectedSidebarTab==3){
        ImGui::SetCursorPos(ImVec2(cx,cy)); begin_category("Movement",colW,160);
        custom_toggle("BunnyHop",&g_bunnyhop);
        end_category();
        ImGui::SetCursorPos(ImVec2(cx+colW+12,cy)); begin_category("Combo",colW,160);
        const char* ci[]={"First","Second","Third"};
        custom_combo("##c",&g_combo,ci,3);
        end_category();
    } else if(self.selectedSidebarTab==4){
        ImGui::SetCursorPos(ImVec2(cx,cy)); begin_category("Misc",colW*2+12,160);
        custom_toggle("Toggle example",&g_esp_box,"With configuration!");
        end_category();
    } else {
        ImGui::SetCursorPos(ImVec2(cx,cy)); begin_category("Configs",colW*2+12,160);
        ImGui::SetCursorPosX(10);
        ImGui::TextColored(ImVec4(0.5f,0.5f,0.58f,1),"No configs yet");
        end_category();
    }

    ImGui::End();
    ImGui::PopStyleColor(2); ImGui::PopStyleVar(3);
    ImGui::Render();
    id<MTLCommandBuffer> cb=[self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> en=[cb renderCommandEncoderWithDescriptor:rp];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(),cb,en);
    [en endEncoding]; [cb presentDrawable:dr]; [cb commit];
}
@end
