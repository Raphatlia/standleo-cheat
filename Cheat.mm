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
#include <cmath>
#include <cstdio>
#include <functional>
#include <unordered_map>
#include <mach-o/dyld.h>
#include <cstring>

// ===== Состояния =====
static bool g_wallbang = true, g_norecoil = true, g_bunnyhop = false;
static bool g_esp_box = true, g_esp_health = true, g_esp_nickname = true;
static bool g_offscreen = false, g_internal = false;
static bool g_wallbang_status = true, g_norecoil_status = true;
static bool g_simple_switch = false, g_auto_strafe = false, g_fast_drop = false;
static int  g_slider = 0;
static int  g_slider2 = 0;
static ImVec4 g_col1 = ImVec4(1,0,0,1), g_col2 = ImVec4(0,1,0,1);

static CGPoint g_touchScreenPos = CGPointZero;

#pragma mark - ===== HOOKS / MEMORY =====
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <cstring>

namespace hooks {
    static uintptr_t g_base = 0;
    static bool g_ready = false;
    
    // ОФСЕТЫ ИЗ DUMP.CS
    namespace off {
        // PlayerControls.GetKeyboardInputs() -> PlayerInputs*
        constexpr uintptr_t get_keyboard_inputs = 0x1F081C0;
        // PlayerControls.GetTouchInputs() -> PlayerInputs*
        constexpr uintptr_t get_touch_inputs = 0x1F081DC;
        
        // PlayerInputs.IsToJump offset
        constexpr uintptr_t is_to_jump = 0x23;
        
        // GunController._recoilMult offset
        constexpr uintptr_t recoil_mult = 0x1A0;
    }
    
    // Найти base UnityFramework
    static uintptr_t find_base() {
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char* n = _dyld_get_image_name(i);
            if (n && strstr(n, "UnityFramework"))
                return (uintptr_t)_dyld_get_image_header(i);
        }
        return 0;
    }
    
    // Inline hook для ARM64
    static bool inline_hook(uintptr_t target, uintptr_t hook, uintptr_t* original) {
        vm_size_t page_size = 4096;
        uintptr_t page_start = target & ~(page_size - 1);
        
        vm_protect(mach_task_self(), page_start, page_size, false,
                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
        
        uint8_t orig_bytes[32];
        memcpy(orig_bytes, (void*)target, 16);
        
        uint32_t* code = (uint32_t*)target;
        code[0] = 0x58000050;
        code[1] = 0xD61F0200;
        *(uintptr_t*)(code + 2) = hook;
        
        uintptr_t tramp = (uintptr_t)malloc(64);
        memcpy((void*)tramp, orig_bytes, 16);
        code = (uint32_t*)(tramp + 16);
        code[0] = 0x58000050;
        code[1] = 0xD61F0200;
        *(uintptr_t*)(code + 2) = target + 16;
        
        if (original) *original = tramp;
        
        vm_protect(mach_task_self(), page_start, page_size, false,
                   VM_PROT_READ | VM_PROT_EXECUTE);
        
        sys_icache_invalidate((void*)target, 16);
        sys_icache_invalidate((void*)tramp, 32);
        
        return true;
    }
    
    // Тип функции GetInputs
    typedef void* (*GetInputs_t)(void* player_controls);
    static GetInputs_t orig_get_keyboard = nullptr;
    static GetInputs_t orig_get_touch = nullptr;
    
    // Хук GetKeyboardInputs
    static void* hk_get_keyboard(void* player_controls) {
        void* ret = orig_get_keyboard(player_controls);
        if (ret && g_bunnyhop) {
            *(bool*)((uintptr_t)ret + off::is_to_jump) = true;
        }
        return ret;
    }
    
    // Хук GetTouchInputs
    static void* hk_get_touch(void* player_controls) {
        void* ret = orig_get_touch(player_controls);
        if (ret && g_bunnyhop) {
            *(bool*)((uintptr_t)ret + off::is_to_jump) = true;
        }
        return ret;
    }
    
    void init() {
        if (g_ready) return;
        g_base = find_base();
        g_ready = (g_base != 0);
        
        if (g_ready) {
            uintptr_t target1 = g_base + off::get_keyboard_inputs;
            inline_hook(target1, (uintptr_t)hk_get_keyboard, (uintptr_t*)&orig_get_keyboard);
            
            uintptr_t target2 = g_base + off::get_touch_inputs;
            inline_hook(target2, (uintptr_t)hk_get_touch, (uintptr_t*)&orig_get_touch);
        }
    }
    
    void update() {
        if (!g_ready) init();
        if (!g_ready) return;
        
        // NoRecoil — заглушка, нужен адрес GunController
        if (g_norecoil) {
            // TODO: найти GunController и записать 0.0f в _recoilMult
        }
    }
}

// ===== Аниматор =====
static float anim_f(ImGuiID id, float target, float dur = 0.10f) {
    static std::unordered_map<ImGuiID,float> m;
    float& cur = m[id];
    float t = ImClamp(ImGui::GetIO().DeltaTime / dur, 0.0f, 1.0f);
    cur += (target - cur) * t;
    if (fabsf(cur - target) < 0.001f) cur = target;
    return cur;
}
static ImVec4 anim_v(ImGuiID id, ImVec4 target, float dur = 0.10f) {
    static std::unordered_map<ImGuiID,ImVec4> m;
    ImVec4& c = m[id];
    float t = ImClamp(ImGui::GetIO().DeltaTime / dur, 0.0f, 1.0f);
    c.x += (target.x-c.x)*t; c.y += (target.y-c.y)*t;
    c.z += (target.z-c.z)*t; c.w += (target.w-c.w)*t;
    return c;
}

static ImFont* logo_font = nullptr;

// ===== internal_toggle =====
static bool internal_toggle(const char* label, bool* v) {
    ImGuiWindow* w = ImGui::GetCurrentWindow();
    if (w->SkipItems) return false;
    const ImGuiStyle& st = ImGui::GetStyle();
    const ImGuiID id = w->GetID(label);
    const ImVec2 ls = ImGui::CalcTextSize(label, NULL, true);
    const float sq = ImGui::GetFrameHeight();
    const ImVec2 pos = w->DC.CursorPos;
    const float width = ImGui::GetContentRegionAvail().x;
    const ImRect total_bb(pos, pos + ImVec2(width, ls.y + st.FramePadding.y*2));
    ImGui::ItemSize(total_bb, st.FramePadding.y);
    if (!ImGui::ItemAdd(total_bb, id)) return false;
    bool hovered, held;
    bool pressed = ImGui::ButtonBehavior(total_bb, id, &hovered, &held);
    if (pressed) *v = !(*v);
    const ImRect check_bb(ImVec2(total_bb.Max.x - sq*2 + 10, total_bb.Min.y + 2), total_bb.Max - ImVec2(0,2));
    float main = anim_f(id, *v?1.f:0.f);
    ImVec4 pill = anim_v(id+1, *v ? ImVec4(0,0,0,1) : ImVec4(55/255.f,55/255.f,66/255.f,1));
    ImVec4 text = anim_v(id+2, (*v||hovered) ? ImVec4(1,1,1,1) : ImVec4(155/255.f,155/255.f,155/255.f,1));
    ImVec4 outl = anim_v(id+3, *v ? ImVec4(1,1,1,1) : ImVec4(55/255.f,55/255.f,66/255.f,1));
    ImVec4 bg   = anim_v(id+4, *v ? ImVec4(25/255.f,25/255.f,25/255.f,1) : ImVec4(25/255.f,25/255.f,25/255.f,0));
    ImDrawList* d = w->DrawList;
    int vs = d->VtxBuffer.Size;
    d->AddRectFilled(check_bb.Min, check_bb.Max, ImGui::ColorConvertFloat4ToU32(bg), 666);
    int ve = d->VtxBuffer.Size;
    if (ve>vs) ImGui::ShadeVertsLinearColorGradientKeepAlpha(d,vs,ve,check_bb.Min,check_bb.Max,IM_COL32(218,221,216,255),IM_COL32(234,193,251,255));
    d->AddRect(check_bb.Min, check_bb.Max, ImGui::ColorConvertFloat4ToU32(outl), 666);
    d->AddCircleFilled(ImVec2(check_bb.Min.x + 8 + 14*main, check_bb.GetCenter().y), 5, ImGui::ColorConvertFloat4ToU32(pill), 200);
    ImGui::PushStyleColor(ImGuiCol_Text, text);
    if (ls.x>0) ImGui::RenderText(total_bb.Min, label);
    ImGui::PopStyleColor();
    return pressed;
}

// ===== toggle =====
static void toggle(const char* label, bool* v, const char* desc, std::function<void()> advanced = nullptr) {
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(10,10));
    ImGui::BeginChild(label, ImVec2(ImGui::GetContentRegionAvail().x - 10, 0), false, ImGuiWindowFlags_AlwaysUseWindowPadding);
    {
        ImRect wr = ImGui::GetCurrentWindow()->Rect();
        ImGui::GetWindowDrawList()->AddRect(wr.Min, wr.Max, ImColor(41,43,55, (int)(ImGui::GetStyle().Alpha*255)), 8, 0, 1);
        ImGui::SetCursorPos(ImVec2(10,10));
        internal_toggle(label, v);
        ImGui::SetCursorPosX(10);
        if (desc) {
            ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(155/255.f,155/255.f,155/255.f,1));
            ImGui::TextWrapped("%s", desc);
            ImGui::PopStyleColor();
        }
        if (advanced) {
            ImGui::SetCursorPosX(0);
            ImVec2 lp = ImGui::GetCursorScreenPos();
            ImGui::GetWindowDrawList()->AddLine(lp, ImVec2(lp.x+ImGui::GetWindowSize().x, lp.y), ImColor(41,43,55,(int)(ImGui::GetStyle().Alpha*255)));
            ImGui::Dummy(ImVec2(0,0));
            ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0,0));
            ImGui::BeginChild((std::string(label)+"##2").c_str(), ImVec2(ImGui::GetContentRegionAvail().x,0), false, ImGuiWindowFlags_AlwaysUseWindowPadding);
            { advanced(); ImGui::EndChild(); }
            ImGui::PopStyleVar();
        }
        ImGui::EndChild();
    }
    ImGui::PopStyleVar();
}

// ===== slider_int =====
static bool slider_int(const char* label, int* v, int vmin, int vmax) {
    ImGuiWindow* w = ImGui::GetCurrentWindow();
    if (w->SkipItems) return false;
    const ImGuiStyle& st = ImGui::GetStyle();
    const ImGuiID id = w->GetID(label);
    const float width = ImGui::GetContentRegionAvail().x;
    const ImVec2 ls = ImGui::CalcTextSize(label, NULL, true);
    const ImVec2 pos = w->DC.CursorPos;
    const float track_h = 5.0f;
    const float gap     = 6.0f;
    const ImRect label_bb(pos, ImVec2(pos.x + width, pos.y + ls.y));
    const ImRect track_bb(ImVec2(pos.x, label_bb.Max.y + gap), ImVec2(pos.x + width, label_bb.Max.y + gap + track_h));
    const ImRect hit_bb(ImVec2(track_bb.Min.x, track_bb.Min.y - 7), ImVec2(track_bb.Max.x, track_bb.Max.y + 7));
    const ImRect total_bb(pos, track_bb.Max);
    ImGui::ItemSize(total_bb, st.FramePadding.y);
    if (!ImGui::ItemAdd(total_bb, id)) return false;
    bool hovered, held;
    bool pressed = ImGui::ButtonBehavior(hit_bb, id, &hovered, &held);
    bool changed = false;
    if (held || pressed) {
        float ratio = ImClamp((ImGui::GetIO().MousePos.x - track_bb.Min.x) / track_bb.GetWidth(), 0.f, 1.f);
        int nv = vmin + (int)roundf(ratio * (vmax - vmin));
        if (nv != *v) { *v = nv; changed = true; }
    }
    ImDrawList* d = w->DrawList;
    ImVec4 text = anim_v(id+6, (held||hovered||changed) ? ImVec4(1,1,1,1) : ImVec4(155/255.f,155/255.f,155/255.f,1));
    char vb[64]; snprintf(vb, sizeof(vb), "%d", *v);
    ImVec2 sep = ImGui::CalcTextSize(">>");
    d->AddText(label_bb.Min, ImGui::ColorConvertFloat4ToU32(text), label);
    d->AddText(ImVec2(label_bb.Min.x + ls.x + 5, label_bb.Min.y), ImColor(65,65,65), ">>");
    d->AddText(ImVec2(label_bb.Min.x + ls.x + 5 + sep.x + 5, label_bb.Min.y), ImColor(155,155,155), vb);
    const float r = track_h * 0.5f;
    d->AddRectFilled(track_bb.Min, track_bb.Max, ImColor(55,55,66,(int)(st.Alpha*255)), r);
    float ratio = (float)(*v - vmin) / (float)(vmax - vmin);
    if (ratio > 0.001f) {
        ImVec2 fill_max(track_bb.Min.x + track_bb.GetWidth() * ratio, track_bb.Max.y);
        int vs = d->VtxBuffer.Size;
        d->AddRectFilled(track_bb.Min, fill_max, ImColor(25,25,25,(int)(st.Alpha*255)), r);
        int ve = d->VtxBuffer.Size;
        if (ve > vs) ImGui::ShadeVertsLinearColorGradientKeepAlpha(d, vs, ve, track_bb.Min, fill_max, IM_COL32(218,221,216,255), IM_COL32(234,193,251,255));
    }
    return changed;
}

// ===== colorpicker =====
static void color(const char* label, std::vector<ImVec4*> colors) {
    ImGuiWindow* w = ImGui::GetCurrentWindow();
    if (w->SkipItems) return;
    const ImGuiStyle& st = ImGui::GetStyle();
    const ImGuiID id = w->GetID(label);
    const ImVec2 ls = ImGui::CalcTextSize(label, NULL, true);
    const float sq = ImGui::GetFrameHeight();
    const float width = ImGui::GetContentRegionAvail().x;
    const ImVec2 pos = w->DC.CursorPos;
    const ImRect total_bb(pos, pos + ImVec2(width, ls.y + st.FramePadding.y*2));
    ImGui::ItemSize(total_bb, st.FramePadding.y);
    if (!ImGui::ItemAdd(total_bb, id)) return;
    ImDrawList* d = w->DrawList;
    ImVec2 min = total_bb.Max - ImVec2(0, sq-2);
    for (int i=0;i<(int)colors.size();i++){
        ImRect cb(ImVec2(min.x - sq*(i+1) - 8*i, min.y), ImVec2(min.x - sq*i - 8*i, total_bb.Max.y-2));
        ImGuiID cid = id*10*(i+1);
        ImGui::ItemAdd(cb, cid);
        bool h2,hd; bool p2 = ImGui::ButtonBehavior(cb, cid, &h2, &hd);
        char pn[48]; snprintf(pn, sizeof(pn), "##col_pop_%d_%d", (int)(id % 100000), i);
        if (p2) ImGui::OpenPopup(pn);
        d->AddRectFilled(cb.Min, cb.Max, ImGui::ColorConvertFloat4ToU32(*colors[i]), 3);
        d->AddRect(cb.Min, cb.Max, ImColor(55,55,66,(int)(st.Alpha*255)), 3);
    }
    if (ls.x>0) d->AddText(total_bb.Min, ImColor(155,155,155), label);
    for (int i=0;i<(int)colors.size();i++){
        char pn[48]; snprintf(pn, sizeof(pn), "##col_pop_%d_%d", (int)(id % 100000), i);
        if (ImGui::BeginPopup(pn)) {
            float a = anim_f(id+7+i,1.f,0.08f);
            ImGui::PushStyleVar(ImGuiStyleVar_Alpha, a*st.Alpha);
            ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(10/255.f,14/255.f,21/255.f,a*st.Alpha));
            ImGui::PushStyleColor(ImGuiCol_Border, ImVec4(25/255.f,32/255.f,40/255.f,a*st.Alpha));
            ImGui::ColorPicker4("##p",(float*)colors[i], ImGuiColorEditFlags_NoInputs|ImGuiColorEditFlags_NoSidePreview|ImGuiColorEditFlags_AlphaBar);
            ImGui::PopStyleColor(2); ImGui::PopStyleVar();
            ImGui::EndPopup();
        } else anim_f(id+7+i,0.f,0.08f);
    }
}

// ===== simple_category =====
static void begin_category(const char* label){
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(10,10));
    ImGui::BeginChild(label, ImVec2(ImGui::GetContentRegionAvail().x-10,0), false, ImGuiWindowFlags_AlwaysUseWindowPadding);
    {
        ImRect wr = ImGui::GetCurrentWindow()->Rect();
        ImGui::GetWindowDrawList()->AddRect(wr.Min, wr.Max, ImColor(41,43,55,(int)(ImGui::GetStyle().Alpha*255)), 8, 0, 1);
        ImGui::Text("%s", label);
        ImGui::SetCursorPosX(0);
        ImVec2 lp = ImGui::GetCursorScreenPos();
        ImGui::GetWindowDrawList()->AddLine(lp, ImVec2(lp.x+ImGui::GetWindowSize().x, lp.y), ImColor(41,43,55,(int)(ImGui::GetStyle().Alpha*255)));
        ImGui::Dummy(ImVec2(0,0));
        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0,0));
        ImGui::BeginChild((std::string(label)+"##2").c_str(), ImVec2(ImGui::GetContentRegionAvail().x,0), false, ImGuiWindowFlags_AlwaysUseWindowPadding);
    }
}
static void end_category(){ ImGui::EndChild(); ImGui::PopStyleVar(); ImGui::EndChild(); ImGui::PopStyleVar(); }

// ===== internal_scroll =====
static void internal_scroll(const char* label){
    ImGuiWindow* w = ImGui::GetCurrentWindow();
    ImVec2 mn = w->InnerRect.Min, mx = w->InnerRect.Max;
    ImGui::SetCursorScreenPos(mn);
    ImGui::InvisibleButton(label, mx-mn);
    ImGuiID id = ImGui::GetID(label);
    ImGuiStorage* s = w->DC.StateStorage;
    bool dragging = s->GetBool(id+0,false);
    float ds = s->GetFloat(id+1,0), ss = s->GetFloat(id+2,0);
    if (ImGui::IsItemActive() && !dragging){ dragging=true; ds=ImGui::GetMousePos().y; ss=ImGui::GetScrollY(); }
    else if (!ImGui::IsMouseDown(0)) dragging=false;
    if (dragging) ImGui::SetScrollY(ss - (ImGui::GetMousePos().y - ds));
    s->SetBool(id+0,dragging); s->SetFloat(id+1,ds); s->SetFloat(id+2,ss);
}

#pragma mark - Metal Host View
@interface UIOverlayHostView : UIView
@end
@implementation UIOverlayHostView
+ (Class)layerClass { return [CAMetalLayer class]; }
- (void)touchesBegan:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e {
    UITouch* touch=[t anyObject];
    g_touchScreenPos=[touch locationInView:nil];
    CGPoint p=[touch locationInView:self];
    ImGui::GetIO().MousePos=ImVec2(p.x,p.y); ImGui::GetIO().MouseDown[0]=true;
}
- (void)touchesMoved:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e {
    UITouch* touch=[t anyObject];
    g_touchScreenPos=[touch locationInView:nil];
    CGPoint p=[touch locationInView:self];
    ImGui::GetIO().MousePos=ImVec2(p.x,p.y);
}
- (void)touchesEnded:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e { ImGui::GetIO().MouseDown[0]=false; }
- (void)touchesCancelled:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e { ImGui::GetIO().MouseDown[0]=false; }
@end

#pragma mark - Manager
@interface AntisocialGUIManager : NSObject
@property (nonatomic, strong) UIView *floatingIcon;
@property (nonatomic, strong) CAGradientLayer *iconGrad;
@property (nonatomic, strong) UIOverlayHostView *hostView;
@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) BOOL isReady, isMenuVisible, isDragging;
@property (nonatomic, assign) int m_current, m_sub;
@property (nonatomic, assign) CGPoint menuOffset, dragStartPos;
@property (nonatomic, assign) CGFloat screenWidth, screenHeight;
@end
@implementation AntisocialGUIManager
static AntisocialGUIManager* sharedInst=nil;
+ (AntisocialGUIManager*)shared { if(!sharedInst) sharedInst=[[self alloc] init]; return sharedInst; }
+ (void)load { for(int i=1;i<=15;i++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(i*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [[AntisocialGUIManager shared] trySetup]; }); }
- (UIWindow*)findKeyWindow { for(UIScene* s in UIApplication.sharedApplication.connectedScenes){ if(![s isKindOfClass:[UIWindowScene class]])continue; for(UIWindow* w in ((UIWindowScene*)s).windows) if(w.isKeyWindow) return w;} return nil; }

// ===== Кнопка: лого "A" + НЕОНОВОЕ пульсирующее свечение =====
- (void)setupFloatingIcon:(UIWindow*)kw {
    CGSize sc = kw.bounds.size;
    CGFloat size = 50.0f;
    CGFloat ix = sc.width - 72, iy = 42;

    self.floatingIcon = [[UIView alloc] initWithFrame:CGRectMake(ix, iy, size, size)];
    self.floatingIcon.backgroundColor = [UIColor colorWithRed:10/255.f green:10/255.f blue:18/255.f alpha:0.95];
    self.floatingIcon.layer.cornerRadius = size * 0.5f;
    self.floatingIcon.layer.borderWidth = 1.0f;
    self.floatingIcon.layer.borderColor = [UIColor colorWithRed:120/255.f green:200/255.f blue:255/255.f alpha:0.5].CGColor;
    self.floatingIcon.layer.masksToBounds = NO;

    // неоновое свечение (базовые параметры)
    self.floatingIcon.layer.shadowColor = [UIColor colorWithRed:120/255.f green:180/255.f blue:255/255.f alpha:1.0].CGColor;
    self.floatingIcon.layer.shadowOffset = CGSizeZero;
    self.floatingIcon.layer.shadowRadius = 12.0f;
    self.floatingIcon.layer.shadowOpacity = 0.9f;

    // векторный путь буквы "A" (как в GUI)
    CAShapeLayer *logoShape = [CAShapeLayer layer];
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(25, 13)];
    [path addLineToPoint:CGPointMake(14, 36)];
    [path addLineToPoint:CGPointMake(19, 36)];
    [path addLineToPoint:CGPointMake(25, 22)];
    [path addLineToPoint:CGPointMake(31, 36)];
    [path addLineToPoint:CGPointMake(36, 36)];
    [path closePath];
    [path moveToPoint:CGPointMake(20, 29)];
    [path addLineToPoint:CGPointMake(30, 29)];
    [path addLineToPoint:CGPointMake(30, 32)];
    [path addLineToPoint:CGPointMake(20, 32)];
    [path closePath];
    logoShape.path = path.CGPath;
    logoShape.fillColor = [UIColor whiteColor].CGColor;
    logoShape.frame = CGRectMake(0,0,size,size);

    // градиент белый->розовый, замаскированный буквой
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = CGRectMake(0,0,size,size);
    grad.colors = @[
        (id)[UIColor colorWithRed:238/255.f green:238/255.f blue:244/255.f alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:234/255.f green:193/255.f blue:251/255.f alpha:1.0].CGColor
    ];
    grad.startPoint = CGPointMake(0,0);
    grad.endPoint = CGPointMake(1,1);
    grad.mask = logoShape;
    [self.floatingIcon.layer addSublayer:grad];
    self.iconGrad = grad;

    // ПУЛЬСАЦИЯ неона (свечение дышит)
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
    pulse.fromValue = @(0.45f);
    pulse.toValue   = @(1.0f);
    pulse.duration  = 1.6f;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    pulse.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.floatingIcon.layer addAnimation:pulse forKey:@"neonPulse"];

    CABasicAnimation *pulseR = [CABasicAnimation animationWithKeyPath:@"shadowRadius"];
    pulseR.fromValue = @(8.0f);
    pulseR.toValue   = @(20.0f);
    pulseR.duration  = 1.6f;
    pulseR.autoreverses = YES;
    pulseR.repeatCount = HUGE_VALF;
    pulseR.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.floatingIcon.layer addAnimation:pulseR forKey:@"neonPulseR"];

    // лёгкое свечение самой буквы (внутри)
    CABasicAnimation *glow = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
    glow.fromValue = @(0.5f);
    glow.toValue   = @(1.0f);
    glow.duration  = 1.6f;
    glow.autoreverses = YES;
    glow.repeatCount = HUGE_VALF;
    logoShape.shadowColor = [UIColor colorWithRed:200/255.f green:160/255.f blue:255/255.f alpha:1.0].CGColor;
    logoShape.shadowRadius = 3.0f;
    [logoShape addAnimation:glow forKey:@"logoGlow"];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMenu)];
    [self.floatingIcon addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleIconPan:)];
    [self.floatingIcon addGestureRecognizer:pan];

    [kw addSubview:self.floatingIcon];
}

- (void)handleIconPan:(UIPanGestureRecognizer*)pan {
    CGPoint translation = [pan translationInView:pan.view.superview];
    CGPoint newCenter = CGPointMake(pan.view.center.x + translation.x, pan.view.center.y + translation.y);
    CGSize sc = [UIScreen mainScreen].bounds.size;
    newCenter.x = MAX(25, MIN(sc.width-25, newCenter.x));
    newCenter.y = MAX(25, MIN(sc.height-25, newCenter.y));
    pan.view.center = newCenter;
    [pan setTranslation:CGPointZero inView:pan.view.superview];
}

- (void)trySetup {
    if(self.hostView) return; UIWindow* kw=[self findKeyWindow]; if(!kw) return;
    CGFloat scale=[UIScreen mainScreen].scale; CGSize sc=kw.bounds.size;
    self.screenWidth=sc.width; self.screenHeight=sc.height;
    CGFloat W=620,H=370, px=(sc.width-W)*0.5, py=(sc.height-H)*0.5;
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
    io.Fonts->TexGlyphPadding=1;
    ImFontConfig mc; mc.FontDataOwnedByAtlas=false;
    io.Fonts->AddFontFromMemoryTTF((void*)font_medium,sizeof(font_medium),14.f*scale,&mc,io.Fonts->GetGlyphRangesCyrillic());
    ImFontConfig lc; lc.FontDataOwnedByAtlas=false;
    logo_font=io.Fonts->AddFontFromMemoryTTF((void*)logo_ttf,sizeof(logo_ttf),48.f*scale,&lc);
    io.FontGlobalScale=1.0f/scale;
    ImGui::GetStyle().WindowRounding=12.f;
    ImGui::GetStyle().Colors[ImGuiCol_Border]=ImColor(41,41,55).Value;
    ImGui::GetStyle().Colors[ImGuiCol_WindowBg]=ImColor(16,16,28).Value;
    ImGui::GetStyle().Colors[ImGuiCol_TextSelectedBg]=ImVec4(0,0,0,0);
    ImGui_ImplMetal_Init(self.device);
    self.m_current=0; self.m_sub=0; self.isReady=YES;
    [self setupFloatingIcon:kw];
    self.displayLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(render)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
- (void)toggleMenu {
    self.isMenuVisible=!self.isMenuVisible;
    self.hostView.hidden=!self.isMenuVisible;
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

    hooks::update();

    static float child_alpha=0.f;
    const float W=620,H=370,left=140,top=40;
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding,ImVec2(0,0));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize,0);
    ImGui::SetNextWindowSize(ImVec2(W,H));
    ImGui::SetNextWindowPos(ImVec2(ImGui::GetIO().DisplaySize.x/2-W/2, ImGui::GetIO().DisplaySize.y/2-H/2), ImGuiCond_Once);
    ImGui::Begin("##main",0,ImGuiWindowFlags_NoDecoration|ImGuiWindowFlags_NoBackground|ImGuiWindowFlags_NoBringToFrontOnFocus);
    {
        ImRect wr=ImGui::GetCurrentWindow()->Rect(); ImDrawList* dl=ImGui::GetWindowDrawList();
        // фон окна (без рамки по периметру)
        int vs=dl->VtxBuffer.Size;
        dl->AddRectFilled(wr.Min,wr.Max,ImColor(16,16,28),ImGui::GetStyle().WindowRounding);
        int ve=dl->VtxBuffer.Size;
        ImGui::ShadeVertsLinearColorGradientKeepAlpha(dl,vs,ve,wr.Min,wr.Max+ImVec2(600,600),IM_COL32(16,16,28,255),IM_COL32(27,15,61,255));

        // ЛЕВЫЙ САЙДБАР
        ImGui::SetCursorPos(ImVec2(0,0));
        ImGui::BeginChild("##left",ImVec2(left,wr.GetHeight()),false);
        {
            if(logo_font){
                ImGui::PushFont(logo_font);
                ImVec2 gs=ImGui::CalcTextSize("A");
                ImGui::SetCursorPos(ImVec2(left/2-gs.x/2,20));
                ImVec2 fill_min=ImGui::GetCursorScreenPos();
                int v1=dl->VtxBuffer.Size;
                ImGui::Text("A");
                int v2=dl->VtxBuffer.Size;
                ImVec2 fill_max=fill_min+gs;
                ImGui::ShadeVertsLinearColorGradientKeepAlpha(dl,v1,v2,fill_min,fill_max,IM_COL32(218,221,216,255),IM_COL32(234,193,251,255));
                ImGui::PopFont();
            }
            ImGui::ItemSize(ImVec2(0,10));
            const char* tabs[]={"Visuals","Combat","World","Movement","Misc","Configs"};
            for(int it=0;it<6;it++){
                ImVec2 cc=ImGui::GetCursorScreenPos();
                ImVec2 ts=ImVec2(left,26);
                if(ImGui::InvisibleButton(tabs[it],ts)){ self.m_current=it; self.m_sub=0; child_alpha=0.f; }
                ImRect tr(cc+ImVec2(11,0), cc+ts-ImVec2(10,0));
                ImVec4 txt=anim_v(ImGui::GetID(tabs[it])+1, (it==self.m_current)?ImVec4(120/255.f,123/255.f,173/255.f,1):ImVec4(220/255.f,220/255.f,220/255.f,1));
                ImVec4 bgc=anim_v(ImGui::GetID(tabs[it])+2, (it==self.m_current)?ImVec4(26/255.f,27/255.f,47/255.f,1):ImVec4(26/255.f,27/255.f,47/255.f,0));
                ImVec4 outl=anim_v(ImGui::GetID(tabs[it])+3, (it==self.m_current)?ImVec4(1,1,1,8/255.f):ImVec4(1,1,1,0));
                int s1=dl->VtxBuffer.Size;
                dl->AddRectFilled(tr.Min,tr.Max,ImGui::ColorConvertFloat4ToU32(bgc),6);
                int s2=dl->VtxBuffer.Size;
                if(s2>s1) ImGui::ShadeVertsLinearColorGradientKeepAlpha(dl,s1,s2,tr.Min,tr.Max,IM_COL32(15,16,34,255),IM_COL32(26,27,47,255));
                dl->AddRect(tr.Min,tr.Max,ImGui::ColorConvertFloat4ToU32(outl),6,0,1);
                ImVec2 tsz=ImGui::CalcTextSize(tabs[it]);
                float pd=tr.GetHeight()/2-tsz.y/2;
                dl->AddText(tr.Min+ImVec2(pd*2,pd),ImGui::ColorConvertFloat4ToU32(txt),tabs[it]);
            }
            ImRect child_wr=ImGui::GetCurrentWindow()->Rect();
            ImRect pr=ImRect(ImVec2(child_wr.Min.x+11,child_wr.Max.y-10-38), child_wr.Max-ImVec2(10,10));
            dl->AddRectFilled(pr.Min,pr.Max,ImColor(255,255,255,7),8);
            dl->AddRect(pr.Min,pr.Max,ImColor(27,29,42),8);
            float rad=pr.GetHeight()/2-6;
            dl->AddCircle(ImVec2(pr.Min.x+rad+6,pr.GetCenter().y),rad,ImColor(255,255,255),64);
            dl->AddText(ImVec2(pr.Min.x+rad*2+12,pr.GetCenter().y-ImGui::CalcTextSize("@STANDLEO").y+1),ImColor(255,255,255),"@STANDLEO");
            dl->AddText(ImVec2(pr.Min.x+rad*2+12,pr.GetCenter().y-1),ImColor(245,215,66),"Premium");
            ImGui::EndChild();
        }

        // ВЕРХНИЕ SUBTABS
        ImGui::SetCursorPos(ImVec2(left,0));
        ImGui::BeginChild("##top",ImVec2(ImGui::GetContentRegionAvail().x,top),false);
        {
            ImGui::SetCursorPosX(ImGui::GetCursorPosX()+5);
            const char* sub[]={"General","Advanced"};
            for(int it=0;it<2;it++){
                ImVec2 cc=ImGui::GetCursorScreenPos();
                ImVec2 ts=ImVec2(ImGui::CalcTextSize(sub[it]).x+20,top);
                if(ImGui::InvisibleButton(sub[it],ts)){ self.m_sub=it; child_alpha=0.f; }
                ImRect tr(cc+ImVec2(0,6),cc+ts-ImVec2(0,5));
                ImVec4 txt=anim_v(ImGui::GetID(sub[it]), (it==self.m_sub)?ImVec4(120/255.f,123/255.f,173/255.f,1):ImVec4(220/255.f,220/255.f,220/255.f,1));
                ImVec2 tsz=ImGui::CalcTextSize(sub[it]);
                dl->AddText(tr.GetCenter()-tsz/2,ImGui::ColorConvertFloat4ToU32(txt),sub[it]);
                ImGui::SameLine(0,0);
            }
            ImGui::EndChild();
        }

        // ===== разделители: почти невидимые, НЕ создают рамок =====
        dl->AddLine(ImVec2(wr.Min.x+left,wr.Min.y+top),ImVec2(wr.Min.x+left,wr.Max.y),ImColor(25,25,35,30),1);
        dl->AddLine(ImVec2(wr.Min.x+left,wr.Min.y+top),ImVec2(wr.Max.x,wr.Min.y+top),ImColor(25,25,35,30),1);

        child_alpha=anim_f(ImGui::GetID("##ca"),1.f,0.15f);
        ImGui::PushStyleVar(ImGuiStyleVar_Alpha,child_alpha);
        ImGui::SetCursorPos(ImVec2(left+11, top+1+(35*(1-child_alpha))));
        float colw=ImGui::GetContentRegionAvail().x/2-0.5f;
        ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing,ImVec2(10,10));
        ImGui::BeginChild("##c1",ImVec2(colw,ImGui::GetContentRegionAvail().y),false,ImGuiWindowFlags_NoScrollbar);
        {
            ImGui::ItemSize(ImVec2(0,0));
            if(self.m_current==0){
                toggle("Box ESP",&g_esp_box,"With configuration!",[]{ internal_toggle("Internal too?",&g_internal); slider_int("And slider??",&g_slider,-5,5); color("Colorpicker",{&g_col1,&g_col2}); });
                toggle("Health Bar",&g_esp_health,nullptr);
                toggle("Nickname",&g_esp_nickname,nullptr);
            } else if(self.m_current==1){
                toggle("Wallbang",&g_wallbang,nullptr);
                toggle("NoRecoil",&g_norecoil,nullptr);
            } else if(self.m_current==2){
                slider_int("And slider??",&g_slider,-5,5);
                color("Colorpicker",{&g_col1,&g_col2});
            } else if(self.m_current==3){
                toggle("BunnyHop",&g_bunnyhop,nullptr);
            } else if(self.m_current==4){
                toggle("Offscreen",&g_offscreen,"With configuration!");
            } else {
                ImGui::TextColored(ImVec4(0.5f,0.5f,0.58f,1),"No configs yet");
            }
            internal_scroll("##left_window");
            ImGui::EndChild();
        }
        ImGui::SameLine(0,0);
        ImGui::BeginChild("##c2",ImVec2(colw,ImGui::GetContentRegionAvail().y),false,ImGuiWindowFlags_NoScrollbar);
        {
            ImGui::ItemSize(ImVec2(0,0));
            if(self.m_current==0){
                begin_category("Category example"); internal_toggle("Simple switch",&g_simple_switch); end_category();
            } else if(self.m_current==1){
                begin_category("Status");
                internal_toggle("Wallbang",&g_wallbang_status);
                internal_toggle("NoRecoil",&g_norecoil_status);
                end_category();
            } else if(self.m_current==2){
                begin_category("Combo"); slider_int("Test slider",&g_slider2,0,100); end_category();
            } else if(self.m_current==3){
                begin_category("Movement"); internal_toggle("Auto Strafe",&g_auto_strafe); end_category();
            } else if(self.m_current==4){
                begin_category("Misc"); internal_toggle("Fast Drop",&g_fast_drop); end_category();
            } else {
                begin_category("Configs"); ImGui::TextColored(ImVec4(0.5f,0.5f,0.58f,1),"Empty"); end_category();
            }
            internal_scroll("##right_window");
            ImGui::EndChild();
        }
        ImGui::PopStyleVar();
        ImGui::PopStyleVar();

        // ===== ПЛАВНЫЙ drag (только верхняя полоса, без рамок) =====
        ImVec2 mp=ImGui::GetIO().MousePos;
        bool inBar=(mp.x>=left&&mp.x<=W&&mp.y>=0&&mp.y<=top);
        if(inBar&&ImGui::IsMouseClicked(0)){
            self.isDragging=YES;
            self.dragStartPos=CGPointMake(g_touchScreenPos.x-self.menuOffset.x, g_touchScreenPos.y-self.menuOffset.y);
        }
        if(self.isDragging&&ImGui::IsMouseDown(0)){
            CGPoint target=CGPointMake(g_touchScreenPos.x-self.dragStartPos.x, g_touchScreenPos.y-self.dragStartPos.y);
            target.x=MAX(0,MIN(target.x,self.screenWidth-W));
            target.y=MAX(0,MIN(target.y,self.screenHeight-H));
            self.menuOffset=CGPointMake(self.menuOffset.x+(target.x-self.menuOffset.x)*0.25,
                                        self.menuOffset.y+(target.y-self.menuOffset.y)*0.25);
            self.hostView.frame=CGRectMake(self.menuOffset.x,self.menuOffset.y,W,H);
        } else if(!ImGui::IsMouseDown(0)) self.isDragging=NO;

        ImGui::End();
    }
    ImGui::PopStyleVar(2);
    ImGui::Render();
    id<MTLCommandBuffer> cb=[self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> en=[cb renderCommandEncoderWithDescriptor:rp];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(),cb,en);
    [en endEncoding];[cb presentDrawable:dr];[cb commit];
}
@end
