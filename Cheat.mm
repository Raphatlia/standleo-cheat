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

// ===== Состояния =====
static bool g_wallbang = true, g_norecoil = true, g_bunnyhop = false;
static bool g_esp_box = true, g_esp_health = true, g_esp_nickname = true;
static bool g_offscreen = false, g_internal = false;
static bool g_simple_switch = false, g_auto_strafe = false, g_fast_drop = false;
static int  g_slider = 0;
static int  g_combo = 0;
static ImVec4 g_col1 = ImVec4(0,1,0,1), g_col2 = ImVec4(1,0,0,1);

// ===== Аниматоры =====
static float anim_f(ImGuiID id, float target, float dur = 0.15f) {
    static std::unordered_map<ImGuiID,float> m;
    float& cur = m[id];
    float t = ImClamp(ImGui::GetIO().DeltaTime / dur, 0.0f, 1.0f);
    cur += (target - cur) * t;
    if (fabsf(cur - target) < 0.001f) cur = target;
    return cur;
}
static ImVec4 anim_v(ImGuiID id, ImVec4 target, float dur = 0.15f) {
    static std::unordered_map<ImGuiID,ImVec4> m;
    ImVec4& c = m[id];
    float t = ImClamp(ImGui::GetIO().DeltaTime / dur, 0.0f, 1.0f);
    c.x += (target.x-c.x)*t; c.y += (target.y-c.y)*t;
    c.z += (target.z-c.z)*t; c.w += (target.w-c.w)*t;
    return c;
}

static ImFont* logo_font = nullptr;

// ===== internal_toggle — КАК В ОРИГИНАЛЕ (тёмный/светлый, не розовый) =====
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
    float main = anim_f(id, *v?1.f:0.f, 0.18f);
    // КАК В ОРИГИНАЛЕ: выключен = тёмный, включен = светлый
    ImVec4 pill = anim_v(id+1, *v ? ImVec4(230/255.f,230/255.f,235/255.f,1) : ImVec4(55/255.f,55/255.f,66/255.f,1));
    ImVec4 text = anim_v(id+2, (*v||hovered) ? ImVec4(1,1,1,1) : ImVec4(155/255.f,155/255.f,155/255.f,1));
    ImVec4 outl = anim_v(id+3, *v ? ImVec4(200/255.f,200/255.f,210/255.f,1) : ImVec4(55/255.f,55/255.f,66/255.f,1));
    ImVec4 bg   = anim_v(id+4, *v ? ImVec4(25/255.f,25/255.f,25/255.f,1) : ImVec4(25/255.f,25/255.f,25/255.f,0));
    ImDrawList* d = w->DrawList;
    int vs = d->VtxBuffer.Size;
    d->AddRectFilled(check_bb.Min, check_bb.Max, ImGui::ColorConvertFloat4ToU32(bg), 666);
    int ve = d->VtxBuffer.Size;
    if (ve>vs) ImGui::ShadeVertsLinearColorGradientKeepAlpha(d,vs,ve,check_bb.Min,check_bb.Max,IM_COL32(218,221,216,255),IM_COL32(234,193,251,255));
    d->AddRect(check_bb.Min, check_bb.Max, ImGui::ColorConvertFloat4ToU32(outl), 666);
    // Кружок ЧЁРНЫЙ когда включен, серый когда выключен
    ImU32 knob_col = *v ? IM_COL32(20,20,25,255) : IM_COL32(130,130,140,255);
    d->AddCircleFilled(ImVec2(check_bb.Min.x + 8 + 14*main, check_bb.GetCenter().y), 5, knob_col, 200);
    ImGui::PushStyleColor(ImGuiCol_Text, text);
    if (ls.x>0) ImGui::RenderText(total_bb.Min, label);
    ImGui::PopStyleColor();
    return pressed;
}

// ===== toggle (карточный с описанием) =====
static void toggle(const char* label, bool* v, const char* desc = nullptr, std::function<void()> advanced = nullptr) {
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

// ===== slider_int — БЕЗ КРУЖКА, градиент белый→розовый =====
static bool slider_int(const char* label, int* v, int vmin, int vmax) {
    ImGuiWindow* w = ImGui::GetCurrentWindow();
    if (w->SkipItems) return false;
    const ImGuiID id = w->GetID(label);
    const float width = ImGui::GetContentRegionAvail().x;
    const ImVec2 pos = w->DC.CursorPos;
    const float h = 28.0f;
    const ImRect bb(pos, ImVec2(pos.x + width, pos.y + h));
    ImGui::ItemSize(bb);
    if (!ImGui::ItemAdd(bb, id)) return false;
    bool hovered, held;
    bool pressed = ImGui::ButtonBehavior(bb, id, &hovered, &held);
    if (held || (pressed && ImGui::IsMouseClicked(0))) {
        float ratio = ImClamp((ImGui::GetIO().MousePos.x - bb.Min.x) / width, 0.f, 1.f);
        int nv = vmin + (int)roundf(ratio * (vmax - vmin));
        if (nv != *v) { *v = nv; pressed = true; }
    }
    ImDrawList* d = w->DrawList;
    char txt[64]; snprintf(txt, sizeof(txt), "%s >> %d", label, *v);
    d->AddText(pos, IM_COL32(235,235,242,255), txt);
    float trkY = pos.y + h - 8;
    ImVec2 trkMin(pos.x, trkY), trkMax(pos.x + width, trkY + 5);
    d->AddRectFilled(trkMin, trkMax, IM_COL32(40,40,55,255), 2.5f);
    float ratio = (float)(*v - vmin) / (float)(vmax - vmin);
    ImVec2 fillMax(trkMin.x + (trkMax.x - trkMin.x) * ratio, trkMax.y);
    d->AddRectFilledMultiColor(trkMin, fillMax,
        IM_COL32(255,255,255,255), IM_COL32(234,193,251,255),
        IM_COL32(234,193,251,255), IM_COL32(255,255,255,255));
    return pressed;
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
        ImGuiID cid = id*100 + i + 1;
        ImGui::ItemAdd(cb, cid);
        bool h2,hd; bool p2 = ImGui::ButtonBehavior(cb, cid, &h2, &hd);
        if (p2) { char pn[32]; snprintf(pn, sizeof(pn), "##col_pop_%d", i); ImGui::OpenPopup(pn); }
        d->AddRectFilled(cb.Min, cb.Max, ImGui::ColorConvertFloat4ToU32(*colors[i]), 3);
        d->AddRect(cb.Min, cb.Max, ImColor(55,55,66,(int)(st.Alpha*255)), 3);
    }
    if (ls.x>0) d->AddText(total_bb.Min, ImColor(155,155,155), label);
    for (int i=0;i<(int)colors.size();i++){
        char pn[32]; snprintf(pn, sizeof(pn), "##col_pop_%d", i);
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

// ===== combo =====
static bool combo(const char* label, int* value, std::vector<std::string> entries) {
    ImGuiWindow* w = ImGui::GetCurrentWindow();
    if (w->SkipItems) return false;
    const ImGuiStyle& st = ImGui::GetStyle();
    const ImGuiID id = w->GetID(label);
    const ImVec2 ls = ImGui::CalcTextSize(label);
    const ImVec2 pos = w->DC.CursorPos;
    const float width = ImGui::GetContentRegionAvail().x;
    const ImRect drop(pos+ImVec2(0,ls.y+5), ImVec2(pos.x+width, pos.y+28+ls.y+5));
    const ImRect total(pos, drop.Max);
    ImGui::ItemSize(total,0);
    if (!ImGui::ItemAdd(total,id,&total)) return false;
    bool hovered,held; bool pressed = ImGui::ButtonBehavior(drop,id,&hovered,&held);
    bool is_open = ImGui::IsPopupOpen("##dd");
    if (pressed) { if (is_open) ImGui::CloseCurrentPopup(); else ImGui::OpenPopup("##dd"); }
    ImVec4 text = anim_v(id+10, (ImGui::IsItemActive()||hovered||is_open)?ImVec4(1,1,1,1):ImVec4(155/255.f,155/255.f,155/255.f,1));
    ImDrawList* d = w->DrawList;
    d->AddRect(drop.Min, drop.Max, ImColor(55,55,66,(int)(st.Alpha*255)), 8);
    d->AddText(total.Min, ImGui::ColorConvertFloat4ToU32(text), label);
    d->AddText(drop.Min+ImVec2(8,6), ImGui::ColorConvertFloat4ToU32(text), entries[*value].c_str());
    ImVec2 ar(drop.Max.x-14, drop.Min.y+10);
    d->AddTriangleFilled(ar, ImVec2(ar.x+8,ar.y), ImVec2(ar.x+4,ar.y+6), ImGui::ColorConvertFloat4ToU32(text));
    if (!is_open) return false;
    ImGui::SetNextWindowPos(ImVec2(drop.Min.x, drop.Max.y+5));
    ImGui::SetNextWindowSize(ImVec2(drop.GetWidth(),0));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding,8);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize,0);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding,ImVec2(8,8));
    ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(16/255.f,16/255.f,28/255.f,1));
    ImGui::PushStyleColor(ImGuiCol_Border, ImVec4(41/255.f,43/255.f,55/255.f,1));
    bool changed = false;
    if (ImGui::BeginPopup("##dd")) {
        ImGui::PopStyleColor(2); ImGui::PopStyleVar(3);
        for (int i=0;i<(int)entries.size();i++){
            ImGuiID item_id = id + 100 + i;
            ImVec2 item_size(ImGui::GetContentRegionAvail().x, 24);
            bool item_hovered = ImGui::IsMouseHoveringRect(ImGui::GetCursorScreenPos(), ImGui::GetCursorScreenPos()+item_size);
            if (ImGui::InvisibleButton(entries[i].c_str(), item_size)) {
                *value = i; changed = true; ImGui::CloseCurrentPopup();
            }
            ImVec4 item_text = anim_v(item_id, (i==*value||item_hovered)?ImVec4(1,1,1,1):ImVec4(155/255.f,155/255.f,155/255.f,1));
            ImDrawList* item_d = ImGui::GetWindowDrawList();
            ImVec2 item_screen = ImGui::GetCursorScreenPos() - item_size;
            if (item_hovered) item_d->AddRectFilled(item_screen, item_screen+item_size, ImColor(255,255,255,15), 4);
            if (i==*value) item_d->AddRect(item_screen, item_screen+item_size, ImColor(234,193,251,180), 4);
            item_d->AddText(item_screen+ImVec2(8,6), ImGui::ColorConvertFloat4ToU32(item_text), entries[i].c_str());
        }
        if (!ImGui::IsWindowHovered() && ImGui::GetIO().MouseClicked[0]) ImGui::CloseCurrentPopup();
        ImGui::EndPopup();
    } else {
        ImGui::PopStyleColor(2); ImGui::PopStyleVar(3);
    }
    return changed;
}

// ===== category =====
static void begin_category(const char* label, float height = 0){
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(10,10));
    float avail_h = height > 0 ? height : ImGui::GetContentRegionAvail().y;
    ImGui::BeginChild(label, ImVec2(ImGui::GetContentRegionAvail().x-10, avail_h), false, ImGuiWindowFlags_AlwaysUseWindowPadding);
    {
        ImRect wr = ImGui::GetCurrentWindow()->Rect();
        ImGui::GetWindowDrawList()->AddRect(wr.Min, wr.Max, ImColor(41,43,55,(int)(ImGui::GetStyle().Alpha*255)), 8, 0, 1);
        ImGui::Text("%s", label);
        ImGui::SetCursorPosX(0);
        ImVec2 lp = ImGui::GetCursorScreenPos();
        ImGui::GetWindowDrawList()->AddLine(lp, ImVec2(lp.x+ImGui::GetWindowSize().x, lp.y), ImColor(41,43,55,(int)(ImGui::GetStyle().Alpha*255)));
        ImGui::Dummy(ImVec2(0,0));
        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0,0));
        ImGui::BeginChild((std::string(label)+"##2").c_str(), ImVec2(ImGui::GetContentRegionAvail().x,ImGui::GetContentRegionAvail().y), false, ImGuiWindowFlags_AlwaysUseWindowPadding);
    }
}
static void end_category(){ ImGui::EndChild(); ImGui::PopStyleVar(); ImGui::EndChild(); ImGui::PopStyleVar(); }

#pragma mark - Metal Host View
@interface UIOverlayHostView : UIView
@end
@implementation UIOverlayHostView
+ (Class)layerClass { return [CAMetalLayer class]; }
- (void)touchesBegan:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e { CGPoint p=[[t anyObject] locationInView:self]; ImGui::GetIO().MousePos=ImVec2(p.x,p.y); ImGui::GetIO().MouseDown[0]=true; }
- (void)touchesMoved:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e { CGPoint p=[[t anyObject] locationInView:self]; ImGui::GetIO().MousePos=ImVec2(p.x,p.y); }
- (void)touchesEnded:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e { ImGui::GetIO().MouseDown[0]=false; }
- (void)touchesCancelled:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e { ImGui::GetIO().MouseDown[0]=false; }
@end

#pragma mark - Manager
@interface AntisocialGUIManager : NSObject
@property (nonatomic, strong) UIView *floatingIcon;
@property (nonatomic, strong) UIOverlayHostView *hostView;
@property (nonatomic, strong) CAMetalLayer *metalLayer;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) BOOL isReady, isMenuVisible, isDragging, wasVisible;
@property (nonatomic, assign) int m_current, m_sub;
@property (nonatomic, assign) CGPoint menuOffset, dragStartPos, iconOffset;
@property (nonatomic, assign) BOOL iconDragging;
@property (nonatomic, assign) float baseW, baseH;
@end
@implementation AntisocialGUIManager
static AntisocialGUIManager* sharedInst=nil;
+ (AntisocialGUIManager*)shared { if(!sharedInst) sharedInst=[[self alloc] init]; return sharedInst; }
+ (void)load { for(int i=1;i<=15;i++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(i*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [[AntisocialGUIManager shared] trySetup]; }); }
- (UIWindow*)findKeyWindow { for(UIScene* s in UIApplication.sharedApplication.connectedScenes){ if(![s isKindOfClass:[UIWindowScene class]])continue; for(UIWindow* w in ((UIWindowScene*)s).windows) if(w.isKeyWindow) return w;} return nil; }

- (void)setupFloatingIcon:(UIWindow*)kw {
    CGSize sc = kw.bounds.size;
    CGFloat size = 48.0f;
    CGFloat ix = sc.width - 70, iy = 42;
    self.iconOffset = CGPointMake(ix, iy);
    
    self.floatingIcon = [[UIView alloc] initWithFrame:CGRectMake(ix, iy, size, size)];
    self.floatingIcon.backgroundColor = [UIColor colorWithRed:16/255.f green:16/255.f blue:28/255.f alpha:0.95];
    self.floatingIcon.layer.cornerRadius = size * 0.5f;
    self.floatingIcon.layer.borderWidth = 1.2f;
    self.floatingIcon.layer.borderColor = [UIColor colorWithRed:234/255.f green:193/255.f blue:251/255.f alpha:0.45].CGColor;
    // Неоновое свечение
    self.floatingIcon.layer.shadowColor = [UIColor colorWithRed:180/255.f green:130/255.f blue:255/255.f alpha:1.0].CGColor;
    self.floatingIcon.layer.shadowOffset = CGSizeZero;
    self.floatingIcon.layer.shadowRadius = 10.0f;
    self.floatingIcon.layer.shadowOpacity = 0.85f;
    self.floatingIcon.layer.masksToBounds = NO;
    
    // Векторный логотип "A" внутри
    CAShapeLayer *logoShape = [CAShapeLayer layer];
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(24, 12)];
    [path addLineToPoint:CGPointMake(14, 33)];
    [path addLineToPoint:CGPointMake(18.5, 33)];
    [path addLineToPoint:CGPointMake(24, 20.5)];
    [path addLineToPoint:CGPointMake(29.5, 33)];
    [path addLineToPoint:CGPointMake(34, 33)];
    [path closePath];
    [path moveToPoint:CGPointMake(19, 26.5)];
    [path addLineToPoint:CGPointMake(29, 26.5)];
    [path addLineToPoint:CGPointMake(29, 29.5)];
    [path addLineToPoint:CGPointMake(19, 29.5)];
    [path closePath];
    logoShape.path = path.CGPath;
    logoShape.fillColor = [UIColor colorWithRed:234/255.f green:193/255.f blue:251/255.f alpha:1.0].CGColor;
    logoShape.shadowColor = [UIColor whiteColor].CGColor;
    logoShape.shadowOffset = CGSizeZero;
    logoShape.shadowRadius = 4.0f;
    logoShape.shadowOpacity = 0.7f;
    [self.floatingIcon.layer addSublayer:logoShape];
    
    // Тап — открыть/закрыть меню
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMenu)];
    [self.floatingIcon addGestureRecognizer:tap];
    
    // Drag — перетаскивание
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleIconPan:)];
    [self.floatingIcon addGestureRecognizer:pan];
    
    [kw addSubview:self.floatingIcon];
}

- (void)handleIconPan:(UIPanGestureRecognizer*)pan {
    CGPoint translation = [pan translationInView:pan.view.superview];
    CGPoint newCenter = CGPointMake(pan.view.center.x + translation.x, pan.view.center.y + translation.y);
    CGSize sc = [UIScreen mainScreen].bounds.size;
    newCenter.x = MAX(24, MIN(sc.width-24, newCenter.x));
    newCenter.y = MAX(24, MIN(sc.height-24, newCenter.y));
    pan.view.center = newCenter;
    [pan setTranslation:CGPointZero inView:pan.view.superview];
    self.iconOffset = CGPointMake(newCenter.x - 24, newCenter.y - 24);
}

- (void)trySetup {
    if(self.hostView) return; UIWindow* kw=[self findKeyWindow]; if(!kw) return;
    CGFloat scale=[UIScreen mainScreen].scale; CGSize sc=kw.bounds.size;
    self.baseW = 620.0f; self.baseH = 370.0f;
    CGFloat px=(sc.width-self.baseW)*0.5, py=(sc.height-self.baseH)*0.5;
    self.menuOffset=CGPointMake(px,py);
    self.hostView=[[UIOverlayHostView alloc] initWithFrame:CGRectMake(px,py,self.baseW,self.baseH)];
    self.hostView.backgroundColor=[UIColor clearColor]; self.hostView.hidden=YES; self.hostView.userInteractionEnabled=NO;
    [kw addSubview:self.hostView];
    self.device=MTLCreateSystemDefaultDevice(); self.commandQueue=[self.device newCommandQueue];
    self.metalLayer=(CAMetalLayer*)self.hostView.layer;
    self.metalLayer.device=self.device; self.metalLayer.pixelFormat=MTLPixelFormatBGRA8Unorm;
    self.metalLayer.framebufferOnly=NO; self.metalLayer.opaque=NO;
    self.metalLayer.backgroundColor=[UIColor clearColor].CGColor; self.metalLayer.contentsScale=scale;
    self.metalLayer.drawableSize=CGSizeMake(self.baseW*scale,self.baseH*scale);
    ImGui::CreateContext(); ImGuiIO& io=ImGui::GetIO();
    io.DisplaySize=ImVec2(self.baseW,self.baseH); io.DisplayFramebufferScale=ImVec2(scale,scale);
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
    self.m_current=0; self.m_sub=0; self.isReady=YES; self.wasVisible=NO;
    [self setupFloatingIcon:kw];
    self.displayLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(render)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
- (void)toggleMenu {
    self.wasVisible = self.isMenuVisible;
    self.isMenuVisible=!self.isMenuVisible;
    self.hostView.hidden=!self.isMenuVisible;
    self.hostView.userInteractionEnabled=self.isMenuVisible;
    if(!self.isMenuVisible){ImGui::GetIO().MouseDown[0]=false;ImGui::GetIO().MousePos=ImVec2(-FLT_MAX,-FLT_MAX);}
}

- (void)render {
    if(!self.isReady||!self.isMenuVisible) return;
    CGSize sz=self.hostView.bounds.size; ImGuiIO& io=ImGui::GetIO();
    if (io.DisplaySize.x!=sz.width||io.DisplaySize.y!=sz.height){ io.DisplaySize=ImVec2(sz.width,sz.height); CGFloat sc=[UIScreen mainScreen].scale; self.metalLayer.drawableSize=CGSizeMake(sz.width*sc,sz.height*sc); }
    id<CAMetalDrawable> dr=[self.metalLayer nextDrawable]; if(!dr) return;
    MTLRenderPassDescriptor* rp=[MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture=dr.texture; rp.colorAttachments[0].loadAction=MTLLoadActionClear;
    rp.colorAttachments[0].storeAction=MTLStoreActionStore; rp.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);
    ImGui_ImplMetal_NewFrame(rp); ImGui::NewFrame();

    const float W=self.baseW, H=self.baseH;
    const float left=W*0.23f, top=40;
    
    float gui_alpha = anim_f(ImGui::GetID("gui_alpha"), 1.0f, 0.25f);
    static int prev_tab = -1;
    if (prev_tab != self.m_current) { prev_tab = self.m_current; }
    float tab_alpha = anim_f(ImGui::GetID("tab_alpha"), 1.0f, 0.20f);

    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding,ImVec2(0,0));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize,0);
    ImGui::PushStyleVar(ImGuiStyleVar_Alpha, gui_alpha);
    ImGui::SetNextWindowPos(ImVec2(0,0), ImGuiCond_Always);
    ImGui::SetNextWindowSize(ImVec2(W,H), ImGuiCond_Always);
    ImGui::Begin("##main",0,ImGuiWindowFlags_NoDecoration|ImGuiWindowFlags_NoBackground|ImGuiWindowFlags_NoBringToFrontOnFocus);
    {
        ImRect wr=ImGui::GetCurrentWindow()->Rect(); ImDrawList* dl=ImGui::GetWindowDrawList();
        int vs=dl->VtxBuffer.Size;
        dl->AddRectFilled(wr.Min,wr.Max,ImColor(16,16,28),ImGui::GetStyle().WindowRounding);
        int ve=dl->VtxBuffer.Size;
        ImGui::ShadeVertsLinearColorGradientKeepAlpha(dl,vs,ve,wr.Min,wr.Max+ImVec2(600,600),IM_COL32(16,16,28,255),IM_COL32(27,15,61,255));

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
                if(ImGui::InvisibleButton(tabs[it],ts)){ self.m_current=it; self.m_sub=0; }
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

        ImGui::SetCursorPos(ImVec2(left,0));
        ImGui::BeginChild("##top",ImVec2(ImGui::GetContentRegionAvail().x,top),false);
        {
            ImGui::SetCursorPosX(ImGui::GetCursorPosX()+5);
            const char* sub[]={"General","Advanced"};
            for(int it=0;it<2;it++){
                ImVec2 cc=ImGui::GetCursorScreenPos();
                ImVec2 ts=ImVec2(ImGui::CalcTextSize(sub[it]).x+20,top);
                if(ImGui::InvisibleButton(sub[it],ts)){ self.m_sub=it; }
                ImRect tr(cc+ImVec2(0,6),cc+ts-ImVec2(0,5));
                ImVec4 txt=anim_v(ImGui::GetID(sub[it]), (it==self.m_sub)?ImVec4(120/255.f,123/255.f,173/255.f,1):ImVec4(220/255.f,220/255.f,220/255.f,1));
                ImVec2 tsz=ImGui::CalcTextSize(sub[it]);
                dl->AddText(tr.GetCenter()-tsz/2,ImGui::ColorConvertFloat4ToU32(txt),sub[it]);
                ImGui::SameLine(0,0);
            }
            ImGui::EndChild();
        }

        dl->AddLine(ImVec2(wr.Min.x+left,wr.Min.y),ImVec2(wr.Min.x+left,wr.Max.y),ImColor(41,43,55,77),1);
        dl->AddLine(ImVec2(wr.Min.x+left,wr.Min.y+top),ImVec2(wr.Max.x,wr.Min.y+top),ImColor(41,43,55,77),1);

        ImGui::SetCursorPos(ImVec2(left+11, top+10));
        float colw=(W-left-22-10)/2;
        float colh=H-top-20;
        ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing,ImVec2(10,10));
        ImGui::PushStyleVar(ImGuiStyleVar_Alpha, tab_alpha);
        
        ImGui::BeginChild("##c1",ImVec2(colw,colh),false,ImGuiWindowFlags_NoScrollbar);
        {
            if (self.m_sub == 0) {
                if(self.m_current==0){
                    toggle("Box ESP",&g_esp_box,"Draws box around enemies");
                    toggle("Health Bar",&g_esp_health,"Shows health indicator");
                    toggle("Nickname",&g_esp_nickname,"Shows player names");
                } else if(self.m_current==1){
                    toggle("Wallbang",&g_wallbang,"Shoot through walls");
                    toggle("NoRecoil",&g_norecoil,"Zero weapon recoil");
                } else if(self.m_current==2){
                    toggle("Offscreen",&g_offscreen,"Shows enemies out of visibility");
                } else if(self.m_current==3){
                    toggle("BunnyHop",&g_bunnyhop,"Auto jump on landing");
                } else if(self.m_current==4){
                    toggle("Fast Drop",&g_fast_drop,"Quick descent");
                } else {
                    ImGui::TextColored(ImVec4(0.5f,0.5f,0.58f,1),"No configs yet");
                }
            } else {
                if(self.m_current==0){
                    slider_int("ESP Distance",&g_slider,0,200);
                    color("ESP Color",{&g_col1,&g_col2});
                } else if(self.m_current==1){
                    slider_int("Wallbang Dmg",&g_slider,0,100);
                } else if(self.m_current==2){
                    combo("Mode",&g_combo,{"Normal","Silent","Legit"});
                } else if(self.m_current==3){
                    slider_int("Bhop Delay",&g_slider,0,50);
                } else if(self.m_current==4){
                    slider_int("Fast Drop H",&g_slider,0,100);
                } else {
                    ImGui::TextColored(ImVec4(0.5f,0.5f,0.58f,1),"Empty");
                }
            }
            ImGui::EndChild();
        }
        ImGui::SameLine(0,10);
        ImGui::BeginChild("##c2",ImVec2(colw,colh),false,ImGuiWindowFlags_NoScrollbar);
        {
            if(self.m_current==0){
                begin_category("Category example", colh-20); internal_toggle("Simple switch",&g_simple_switch); end_category();
            } else if(self.m_current==1){
                begin_category("Status", colh-20);
                internal_toggle("Wallbang",&g_wallbang);
                internal_toggle("NoRecoil",&g_norecoil);
                end_category();
            } else if(self.m_current==2){
                begin_category("Combo", colh-20); combo("##combo_hidden",&g_combo,{"First","Second","Third"}); end_category();
            } else if(self.m_current==3){
                begin_category("Movement", colh-20); internal_toggle("Auto Strafe",&g_auto_strafe); end_category();
            } else if(self.m_current==4){
                begin_category("Misc", colh-20); internal_toggle("Fast Drop",&g_fast_drop); end_category();
            } else {
                begin_category("Configs", colh-20); ImGui::TextColored(ImVec4(0.5f,0.5f,0.58f,1),"Empty"); end_category();
            }
            ImGui::EndChild();
        }
        ImGui::PopStyleVar(2);

        ImGui::End();
    }
    ImGui::PopStyleVar(3);

    ImGui::Render();
    id<MTLCommandBuffer> cb=[self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> en=[cb renderCommandEncoderWithDescriptor:rp];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(),cb,en);
    [en endEncoding];[cb presentDrawable:dr];[cb commit];
}
@end
