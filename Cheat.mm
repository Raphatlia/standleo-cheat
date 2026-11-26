#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include "imgui.h"
#include "imgui_internal.h"
#include "imgui_impl_metal.h"
#include "font.hpp"   // font_medium
#include "logo.hpp"   // logo_ttf

// ===== Состояния =====
static bool g_wallbang=true, g_norecoil=true, g_bunnyhop=false;
static bool g_esp_box=true, g_esp_health=true, g_esp_nick=true, g_offscreen=false;
static int  g_fov=90, g_mindmg=30, g_hitbox=0;
static float g_fade=0.0f;

// ===== Скрытый свайп-скролл =====
static void TouchScroll() {
    ImGuiWindow* w = ImGui::GetCurrentWindow();
    if (!w) return;
    if (w->ScrollMax.y <= 0) return;
    if (ImGui::IsMouseDragging(ImGuiMouseButton_Left, 4.0f) &&
        ImGui::IsWindowHovered(ImGuiHoveredFlags_AllowWhenBlockedByActiveItem, w)) {
        w->Scroll.y = ImClamp(w->Scroll.y - ImGui::GetIO().MouseDelta.y, 0.0f, w->ScrollMax.y);
    }
}

// ===== Логотип (глиф "A" из logo_ttf) =====
static void DrawLogo(ImDrawList* d, ImFont* f, ImVec2 c) {
    if (!f) return;
    const char* g = "A";
    ImVec2 sz = ImGui::CalcTextSize(g);
    d->AddCircleFilled(c, f->FontSize*0.62f, IM_COL32(15,14,24,255));
    d->AddCircle(c, f->FontSize*0.62f, IM_COL32(234,193,251,70), 0, 1.0f);
    d->AddText(f, f->FontSize, ImVec2(c.x-sz.x*0.5f, c.y-sz.y*0.5f), IM_COL32(238,238,244,255), g);
}

// ===== Pill-тумблер =====
static bool PillToggle(const char* label, const char* sub, bool* v, float w) {
    ImGuiWindow* win = ImGui::GetCurrentWindow();
    if (win->SkipItems) return false;
    ImGuiID id = win->GetID(label);
    float h = 50.0f;
    ImVec2 p = win->DC.CursorPos;
    ImRect bb(p, ImVec2(p.x+w, p.y+h));
    ImGui::ItemSize(bb);
    if (!ImGui::ItemAdd(bb, id)) return false;
    bool hov, held;
    bool pr = ImGui::ButtonBehavior(bb, id, &hov, &held);
    if (pr) *v = !(*v);
    ImDrawList* d = ImGui::GetWindowDrawList();
    d->AddRectFilled(bb.Min, bb.Max, IM_COL32(19,18,30,255), 12.0f);
    d->AddRect(bb.Min, bb.Max, IM_COL32(255,255,255,hov?36:16), 12.0f, 0, 1.0f);
    d->AddText(ImVec2(p.x+14, p.y+ (sub?10:15)), IM_COL32(235,235,242,255), label);
    if (sub) d->AddText(ImVec2(p.x+14, p.y+28), IM_COL32(120,120,138,255), sub);
    float tw=34, th=18;
    ImVec2 tmin(bb.Max.x-tw-14, p.y+(h-th)*0.5f), tmax(tmin.x+tw, tmin.y+th);
    d->AddRectFilled(tmin, tmax, *v?IM_COL32(124,92,255,255):IM_COL32(40,40,55,255), th*0.5f);
    float kx = *v?(tmax.x-9):(tmin.x+9);
    d->AddCircleFilled(ImVec2(kx,tmin.y+th*0.5f), 7, IM_COL32(0,0,0,60));
    d->AddCircleFilled(ImVec2(kx,tmin.y+th*0.5f-0.5f), 6.5f, IM_COL32(255,255,255,255));
    return pr;
}

// ===== Слайдер =====
static void IntSlider(const char* label, int* v, int mn, int mx, float w) {
    ImGuiWindow* win = ImGui::GetCurrentWindow();
    if (win->SkipItems) return;
    ImGuiID id = win->GetID(label);
    float h=34;
    ImVec2 p = win->DC.CursorPos;
    ImRect bb(p, ImVec2(p.x+w, p.y+h));
    ImGui::ItemSize(bb);
    if (!ImGui::ItemAdd(bb, id)) return;
    ImDrawList* d = ImGui::GetWindowDrawList();
    d->AddText(ImVec2(p.x+14, p.y+4), IM_COL32(235,235,242,255), label);
    char val[16]; snprintf(val,sizeof val,"%d",*v);
    d->AddText(ImVec2(bb.Max.x-50, p.y+4), IM_COL32(124,92,255,255), val);
    float tx=p.x+14, ty=p.y+22, tw=w-28, th=4;
    d->AddRectFilled(ImVec2(tx,ty), ImVec2(tx+tw,ty+th), IM_COL32(40,40,55,255), 2);
    float t = (float)(*v-mn)/(mx-mn);
    d->AddRectFilled(ImVec2(tx,ty), ImVec2(tx+tw*t,ty+th), IM_COL32(124,92,255,255), 2);
    ImVec2 k(tx+tw*t, ty+th*0.5f);
    d->AddCircleFilled(k, 6, IM_COL32(238,238,244,255));
    if (ImGui::IsItemActive()|| (ImGui::IsMouseDown(0)&&ImGui::IsItemHovered())) {
        float nx = ImGui::GetIO().MousePos.x;
        float nt = ImClamp((nx-tx)/tw,0,1);
        *v = mn + (int)roundf(nt*(mx-mn));
    }
}

// ===== Карточка =====
static void BeginCard(const char* t, float w, float h) {
    ImVec2 p = ImGui::GetCursorScreenPos();
    ImDrawList* d = ImGui::GetWindowDrawList();
    d->AddRectFilled(p, ImVec2(p.x+w,p.y+h), IM_COL32(16,15,26,255), 12.0f);
    d->AddRect(p, ImVec2(p.x+w,p.y+h), IM_COL32(255,255,255,22), 12.0f, 0, 1.0f);
    d->AddText(ImVec2(p.x+16,p.y+12), IM_COL32(235,235,242,255), t);
    d->AddLine(ImVec2(p.x,p.y+40), ImVec2(p.x+w,p.y+40), IM_COL32(255,255,255,16), 1.0f);
    ImGui::BeginGroup();
    ImGui::SetCursorScreenPos(ImVec2(p.x+12,p.y+48));
}
static void EndCard() { ImGui::EndGroup(); }

// ===== Хост =====
@interface UIOverlayHostView : UIView @end
@implementation UIOverlayHostView
+ (Class)layerClass { return [CAMetalLayer class]; }
- (void)touchesBegan:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e {
    CGPoint p=[[t anyObject] locationInView:self];
    ImGui::GetIO().MousePos=ImVec2(p.x,p.y); ImGui::GetIO().MouseDown[0]=true; }
- (void)touchesMoved:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e {
    CGPoint p=[[t anyObject] locationInView:self];
    ImGui::GetIO().MousePos=ImVec2(p.x,p.y); }
- (void)touchesEnded:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e { ImGui::GetIO().MouseDown[0]=false; }
- (void)touchesCancelled:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e { ImGui::GetIO().MouseDown[0]=false; }
@end

@interface AntisocialGUI : NSObject
@property(strong)UIButton*btn; @property(strong)UIOverlayHostView*host;
@property(strong)CAMetalLayer*ml; @property(strong)id<MTLDevice>dev;
@property(strong)id<MTLCommandQueue>q; @property(strong)CADisplayLink*link;
@property(assign)BOOL ready,show; @property(assign)int tab,sub;
@property(assign)ImFont*mainF,*logoF;
@property(assign)CGFloat W,H; @property(assign)CGPoint off,dragStart; @property(assign)BOOL drag;
@end
@implementation AntisocialGUI
static AntisocialGUI* S=nil;
+(AntisocialGUI*)shared{ if(!S)S=[[AntisocialGUI alloc]init]; return S; }
+(void)load{ for(int i=1;i<=15;i++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(i*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [[AntisocialGUI shared]setup]; }); }
-(UIWindow*)win{ for(UIScene*s in UIApplication.sharedApplication.connectedScenes){ if(![s isKindOfClass:[UIWindowScene class]])continue; for(UIWindow*w in ((UIWindowScene*)s).windows) if(w.isKeyWindow)return w;} return nil; }

-(void)setup{
    if(self.host)return;
    UIWindow*k=[self win]; if(!k)return;
    CGFloat sc=[UIScreen mainScreen].scale; CGSize ss=k.bounds.size;
    self.W=MIN(560.0f, ss.width*0.82f); self.H=MIN(360.0f, ss.height*0.62f);
    self.off=CGPointMake((ss.width-self.W)*0.5f,(ss.height-self.H)*0.5f);

    self.host=[[UIOverlayHostView alloc]initWithFrame:CGRectMake(self.off.x,self.off.y,self.W,self.H)];
    self.host.backgroundColor=[UIColor clearColor]; self.host.hidden=YES; self.host.userInteractionEnabled=NO;
    [k addSubview:self.host];

    self.dev=MTLCreateSystemDefaultDevice(); self.q=[self.dev newCommandQueue];
    self.ml=(CAMetalLayer*)self.host.layer;
    self.ml.device=self.dev; self.ml.pixelFormat=MTLPixelFormatBGRA8Unorm;
    self.ml.framebufferOnly=NO; self.ml.opaque=NO; self.ml.backgroundColor=[UIColor clearColor].CGColor;
    self.ml.contentsScale=sc; self.ml.drawableSize=CGSizeMake(self.W*sc,self.H*sc);

    ImGui::CreateContext();
    ImGuiIO& io=ImGui::GetIO();
    io.DisplaySize=ImVec2(self.W,self.H); io.DisplayFramebufferScale=ImVec2(sc,sc);
    io.ConfigFlags|=ImGuiConfigFlags_NoMouseCursorChange;
    ImFontConfig cfg; cfg.FontDataOwnedByAtlas=false;
    self.mainF=io.Fonts->AddFontFromMemoryTTF((void*)font_medium,sizeof(font_medium),14.0f*sc,&cfg,io.Fonts->GetGlyphRangesCyrillic());
    self.logoF=io.Fonts->AddFontFromMemoryTTF((void*)logo_ttf,sizeof(logo_ttf),44.0f*sc,&cfg);
    io.FontGlobalScale=1.0f/sc;
    ImGui_ImplMetal_Init(self.dev);

    ImGuiStyle& st=ImGui::GetStyle();
    st.ScrollbarSize=0.0f; st.WindowRounding=12; st.ChildRounding=10; st.FrameRounding=8;
    st.WindowPadding={0,0}; st.ItemSpacing={10,8}; st.WindowBorderSize=0;
    ImVec4* c=st.Colors;
    c[ImGuiCol_Text]={0.92f,0.92f,0.96f,1}; c[ImGuiCol_TextDisabled]={0.42f,0.42f,0.52f,1};
    c[ImGuiCol_WindowBg]={0,0,0,0}; c[ImGuiCol_Border]={0.16f,0.17f,0.22f,1};
    c[ImGuiCol_ScrollbarBg]={0,0,0,0}; c[ImGuiCol_ScrollbarGrab]={0,0,0,0};
    c[ImGuiCol_ScrollbarGrabHovered]={0,0,0,0}; c[ImGuiCol_ScrollbarGrabActive]={0,0,0,0};

    self.tab=1; self.sub=0; self.ready=YES;

    self.btn=[UIButton buttonWithType:UIButtonTypeSystem];
    self.btn.frame=CGRectMake(ss.width-70,44,50,50);
    self.btn.backgroundColor=[UIColor colorWithRed:0.06 green:0.06 blue:0.11 alpha:0.92];
    self.btn.layer.cornerRadius=25; self.btn.layer.borderWidth=1.2f;
    self.btn.layer.borderColor=[UIColor colorWithRed:0.92 green:0.76 blue:0.98 alpha:0.4].CGColor;
    self.btn.layer.shadowColor=[UIColor colorWithRed:0.49 green:0.36 blue:1.0 alpha:0.6].CGColor;
    self.btn.layer.shadowRadius=8; self.btn.layer.shadowOpacity=1;
    [self.btn setTitle:@"A" forState:UIControlStateNormal];
    [self.btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.btn.titleLabel.font=[UIFont systemFontOfSize:22 weight:UIFontWeightHeavy];
    [self.btn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.btn addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panBtn)]];
    [k addSubview:self.btn];

    self.link=[CADisplayLink displayLinkWithTarget:self selector:@selector(render)];
    [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
-(void)panBtn:(UIPanGestureRecognizer*)g{
    UIView* sv=g.view.superview; if(!sv)return;
    CGPoint t=[g translationInView:sv];
    CGPoint nc=CGPointMake(g.view.center.x+t.x, g.view.center.y+t.y);
    CGFloat hs=g.view.bounds.size.width*0.5f;
    nc.x=MAX(hs+6,MIN(sv.bounds.size.width-hs-6,nc.x));
    nc.y=MAX(hs+6,MIN(sv.bounds.size.height-hs-6,nc.y));
    g.view.center=nc; [g setTranslation:CGPointZero inView:sv];
}
-(void)toggle{
    self.show=!self.show; self.host.hidden=!self.show; self.host.userInteractionEnabled=self.show;
    if(self.show)g_fade=0.0f;
    else { ImGui::GetIO().MouseDown[0]=false; ImGui::GetIO().MousePos={-FLT_MAX,-FLT_MAX}; }
}

-(void)render{
    if(!self.ready||!self.show)return;
    id<CAMetalDrawable> dr=[self.ml nextDrawable]; if(!dr)return;
    MTLRenderPassDescriptor* rp=[MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture=dr.texture; rp.colorAttachments[0].loadAction=MTLLoadActionClear;
    rp.colorAttachments[0].storeAction=MTLStoreActionStore; rp.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);
    ImGui_ImplMetal_NewFrame(rp); ImGui::NewFrame();
    g_fade=ImClamp(g_fade+ImGui::GetIO().DeltaTime*6.0f,0,1);
    float a=g_fade;

    const float W=self.W,H=self.H,sw=140.0f,th=44.0f;
    ImGui::SetNextWindowPos({0,0},ImGuiCond_Always);
    ImGui::SetNextWindowSize({W,H},ImGuiCond_Always);
    ImGui::Begin("##ui",nullptr,ImGuiWindowFlags_NoResize|ImGuiWindowFlags_NoCollapse|ImGuiWindowFlags_NoMove|ImGuiWindowFlags_NoTitleBar|ImGuiWindowFlags_NoBackground);
    ImDrawList* d=ImGui::GetWindowDrawList(); ImVec2 wp=ImGui::GetWindowPos();

    // фон окна (скруглённый) + градиентная подложка
    d->AddRectFilledMultiColor(wp,{wp.x+W,wp.y+H},
        IM_COL32(16*a,16*a,28*a,255),IM_COL32(20*a,17*a,40*a,255),
        IM_COL32(27*a,15*a,61*a,255),IM_COL32(18*a,15*a,45*a,255));
    d->AddRect(wp,{wp.x+W,wp.y+H},IM_COL32(41,43,55,(int)(255*a)),12,0,1.5f);
    // сайдбар
    d->AddRectFilled(wp,{wp.x+sw,wp.y+H},IM_COL32(15*a,14*a,24*a,255),12,ImDrawFlags_RoundCornersLeft);
    d->AddLine({wp.x+sw,wp.y},{wp.x+sw,wp.y+H},IM_COL32(41,43,55,(int)(255*a)),1);
    d->AddLine({wp.x+sw,wp.y+th},{wp.x+W,wp.y+th},IM_COL32(41,43,55,(int)(255*a)),1);

    DrawLogo(d,self.logoF,{wp.x+sw*0.5f,wp.y+30});

    const char* tabs[]={"Visuals","Combat","World","Movement","Misc","Configs","Inventory"};
    ImGui::SetCursorPos({12,64});
    ImGui::PushStyleVar(ImGuiStyleVar_ButtonTextAlign,{0,0.5f});
    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding,{14,0});
    ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding,8);
    for(int i=0;i<7;i++){
        bool sel=(self.tab==i);
        ImVec2 cp=ImGui::GetCursorScreenPos();
        if(sel){ d->AddRectFilled(cp,{cp.x+sw-24,cp.y+32},IM_COL32(28,26,46,(int)(255*a)),8);
                 d->AddRectFilled({cp.x,cp.y+7},{cp.x+3,cp.y+25},IM_COL32(124,92,255,(int)(255*a)),2); }
        ImGui::PushStyleColor(ImGuiCol_Button,{0,0,0,0});
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered,{0.12f,0.11f,0.18f,a});
        ImGui::PushStyleColor(ImGuiCol_Text, sel?ImVec4(0.95f,0.95f,0.98f,a):ImVec4(0.5f,0.5f,0.6f,a));
        if(ImGui::Button(tabs[i],{sw-24,32})) self.tab=i;
        ImGui::PopStyleColor(3); ImGui::Dummy({0,2});
    }
    ImGui::PopStyleVar(3);
    // профиль
    d->AddText({wp.x+16,wp.y+H-34},IM_COL32(235,235,242,(int)(255*a)),"STANDLEO");
    ImVec2 br={wp.x+sw-58,wp.y+H-36};
    d->AddRectFilled(br,{br.x+44,br.y+16},IM_COL32(245,215,66,(int)(40*a)),8);
    d->AddText({br.x+8,br.y+2},IM_COL32(245,215,66,(int)(255*a)),"Premium");

    // subtabs
    const char* tops[]={"General","Advanced"};
    ImGui::SetCursorPos({sw+18,10});
    for(int i=0;i<2;i++){
        bool sel=(self.sub==i);
        ImGui::PushStyleColor(ImGuiCol_Button,{0,0,0,0});
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered,{0,0,0,0});
        ImGui::PushStyleColor(ImGuiCol_Text, sel?ImVec4(0.95f,0.95f,0.98f,a):ImVec4(0.48f,0.48f,0.56f,a));
        if(ImGui::Button(tops[i],{78,24})) self.sub=i;
        ImGui::PopStyleColor(3); ImGui::SameLine(0,10);
    }

    // drag окна за titlebar
    ImVec2 mp=ImGui::GetIO().MousePos;
    bool inBar=(mp.x>=sw&&mp.x<=W&&mp.y>=0&&mp.y<=th);
    if(inBar&&ImGui::IsMouseDown(0)){
        if(!self.drag){ self.drag=YES; self.dragStart=CGPointMake(mp.x-self.off.x,mp.y-self.off.y); }
    }
    if(self.drag&&ImGui::IsMouseDown(0)){
        CGPoint n=CGPointMake(mp.x-self.dragStart.x,mp.y-self.dragStart.y);
        n.x=MAX(0,MIN([UIScreen mainScreen].bounds.size.width-W,n.x));
        n.y=MAX(0,MIN([UIScreen mainScreen].bounds.size.height-H,n.y));
        self.off=n; self.host.frame=CGRectMake(n.x,n.y,W,H);
    }
    if(!ImGui::IsMouseDown(0)) self.drag=NO;

    // контент со скрытым свайп-скроллом
    float cx=sw+18, cy=th+16, cw=W-sw-36;
    ImGui::BeginChild("##content",{cw,H-th-32},false,ImGuiWindowFlags_NoScrollbar);
    if(self.tab==0){ BeginCard("ESP",cw,180);
        PillToggle("Box ESP","Draws box around enemies",&g_esp_box,cw-24);
        PillToggle("Health Bar","Shows health indicator",&g_esp_health,cw-24);
        PillToggle("Nickname","Shows player names",&g_esp_nick,cw-24);
        EndCard(); }
    else if(self.tab==1){ BeginCard("Combat",cw,180);
        PillToggle("Wallbang","Shoot through walls",&g_wallbang,cw-24);
        PillToggle("NoRecoil","Zero weapon recoil",&g_norecoil,cw-24);
        EndCard();
        if(self.sub==1){ ImGui::SetCursorPosY(ImGui::GetCursorPosY()+6); BeginCard("Aim",cw,150);
            IntSlider("FOV",&g_fov,0,180,cw-24); IntSlider("Min damage",&g_mindmg,0,200,cw-24);
            EndCard(); } }
    else if(self.tab==3){ BeginCard("Movement",cw,120);
        PillToggle("BunnyHop","Auto jump on landing",&g_bunnyhop,cw-24); EndCard(); }
    else if(self.tab==4){ BeginCard("Misc",cw,120);
        PillToggle("Offscreen","Out-of-view indicators",&g_offscreen,cw-24); EndCard(); }
    else { ImGui::SetCursorPosY(20); ImGui::TextColored({0.5f,0.5f,0.58f,a},"%s: coming soon",tabs[self.tab]); }
    TouchScroll();
    ImGui::EndChild();

    ImGui::End();
    ImGui::Render();
    id<MTLCommandBuffer> cb=[self.q commandBuffer];
    id<MTLRenderCommandEncoder> en=[cb renderCommandEncoderWithDescriptor:rp];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(),cb,en);
    [en endEncoding]; [cb presentDrawable:dr]; [cb commit];
}
@end
