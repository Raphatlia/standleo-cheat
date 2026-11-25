#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import "imgui.h"
#import "imgui_impl_metal.h"
#include "medium.hpp"   // шрифт Instrument Sans (тот самый, что в скрине)

static bool g_offscreen=false, g_esp_rect=false, g_esp_health=false;
static bool g_wallbang=true, g_norecoil=true, g_bunnyhop=false;

// ===== Кастомный toggle как в Concept (трек + белый кружок + подпись) =====
static void ToggleRow(const char* label, bool* v, const char* sub) {
    ImGui::PushID(label);
    ImVec2 p = ImGui::GetCursorScreenPos();
    float w = ImGui::GetContentRegionAvail().x;
    float h = 44;
    ImDrawList* dl = ImGui::GetWindowDrawList();

    // заголовок жирным
    ImGui::SetCursorScreenPos(ImVec2(p.x, p.y + 4));
    ImGui::Text("%s", label);
    // подпись мелким серым
    if (sub) {
        ImGui::SetCursorScreenPos(ImVec2(p.x, p.y + 24));
        ImGui::TextDisabled("%s", sub);
    }
    // трек справа
    float tx = p.x + w - 44, ty = p.y + (h - 18) * 0.5f;
    dl->AddRectFilled(ImVec2(tx, ty), ImVec2(tx + 36, ty + 18),
        *v ? IM_COL32(124, 92, 255, 255) : IM_COL32(40, 40, 55, 255), 9.0f);
    dl->AddCircleFilled(ImVec2(*v ? tx + 27 : tx + 9, ty + 9), 7.0f, IM_COL32(255,255,255,255));

    // клик по всей строке
    ImGui::SetCursorScreenPos(p);
    if (ImGui::InvisibleButton("##t", ImVec2(w, h))) *v = !(*v);
    ImGui::PopID();
    ImGui::Spacing();
}

// ===== карточка =====
static void Card(const char* title, float w, float h, std::function<void()> body) {
    ImVec2 p = ImGui::GetCursorScreenPos();
    ImDrawList* dl = ImGui::GetWindowDrawList();
    dl->AddRectFilled(p, ImVec2(p.x + w, p.y + h), IM_COL32(16,16,26,255), 10.0f);
    dl->AddRect(p, ImVec2(p.x + w, p.y + h), IM_COL32(30,30,46,255), 10.0f, 0, 1.0f);
    ImGui::SetCursorScreenPos(ImVec2(p.x + 12, p.y + 10));
    ImGui::TextColored(ImVec4(0.85f,0.85f,0.92f,1), "%s", title);
    ImGui::SetCursorScreenPos(ImVec2(p.x + 12, p.y + 34));
    body();
    ImGui::SetCursorScreenPos(ImVec2(p.x, p.y + h + 8));
}

@interface CheatHostView : UIView @end
@implementation CheatHostView
+ (Class)layerClass { return [CAMetalLayer class]; }
- (void)touchesBegan:(NSSet*)t withEvent:(UIEvent*)e {
    ImGui::GetIO().MousePos = ImVec2([[t anyObject] locationInView:self].x, [[t anyObject] locationInView:self].y);
    ImGui::GetIO().MouseDown[0] = true;
}
- (void)touchesMoved:(NSSet*)t withEvent:(UIEvent*)e {
    ImGui::GetIO().MousePos = ImVec2([[t anyObject] locationInView:self].x, [[t anyObject] locationInView:self].y);
}
- (void)touchesEnded:(NSSet*)t withEvent:(UIEvent*)e { ImGui::GetIO().MouseDown[0] = false; }
- (void)touchesCancelled:(NSSet*)t withEvent:(UIEvent*)e { ImGui::GetIO().MouseDown[0] = false; }
@end

@interface CheatManager : NSObject
@property(strong)UIButton*button; @property(strong)CheatHostView*host;
@property(strong)CAMetalLayer*ml; @property(strong)id<MTLDevice>dev;
@property(strong)id<MTLCommandQueue>q; @property(strong)CADisplayLink*link;
@property(assign)BOOL ready,show; @property(assign)int tab;
@end
@implementation CheatManager
static CheatManager*g=nil;
+(CheatManager*)shared{ if(!g)g=[[CheatManager alloc]init]; return g; }
+(void)load{ for(int i=1;i<=20;i++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(i*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [[CheatManager shared]trySetup]; }); }
-(UIWindow*)keyWin{ for(UIScene*s in UIApplication.sharedApplication.connectedScenes){ if(![s isKindOfClass:[UIWindowScene class]])continue; for(UIWindow*w in ((UIWindowScene*)s).windows) if(w.isKeyWindow)return w;} return nil; }

-(void)trySetup{
    if(self.host)return;
    UIWindow*win=[self keyWin]; if(!win)return;
    CGFloat scale=[UIScreen mainScreen].scale; CGSize pts=win.bounds.size;

    self.host=[[CheatHostView alloc]initWithFrame:CGRectMake(10,120,440,360)];
    self.host.backgroundColor=[UIColor clearColor];
    self.host.hidden=YES; self.host.userInteractionEnabled=NO;
    [win addSubview:self.host];

    self.dev=MTLCreateSystemDefaultDevice(); self.q=[self.dev newCommandQueue];
    self.ml=(CAMetalLayer*)self.host.layer;
    self.ml.device=self.dev; self.ml.pixelFormat=MTLPixelFormatBGRA8Unorm;
    self.ml.framebufferOnly=NO; self.ml.opaque=NO;
    self.ml.backgroundColor=[UIColor clearColor].CGColor;
    self.ml.contentsScale=scale;
    self.ml.drawableSize=CGSizeMake(440*scale,360*scale);

    ImGui::CreateContext();
    ImGuiIO& io=ImGui::GetIO();
    io.DisplaySize=ImVec2(440,360);
    io.DisplayFramebufferScale=ImVec2(scale,scale);
    io.ConfigFlags|=ImGuiConfigFlags_NoMouseCursorChange;
    io.Fonts->AddFontFromMemoryTTF(instrument_sans_medium_ttf, sizeof instrument_sans_medium_ttf, 13.f*2, nullptr, io.Fonts->GetGlyphRangesCyrillic());
    io.FontGlobalScale=0.5f;
    ImGui_ImplMetal_Init(self.dev);

    ImGuiStyle& st=ImGui::GetStyle();
    st.WindowRounding=12; st.ChildRounding=10; st.FrameRounding=8; st.TabRounding=8;
    st.WindowPadding={14,14}; st.ItemSpacing={10,8}; st.WindowBorderSize=1; st.ChildBorderSize=0;
    ImVec4* c=st.Colors;
    c[ImGuiCol_Text]={0.92f,0.92f,0.96f,1}; c[ImGuiCol_TextDisabled]={0.42f,0.42f,0.52f,1};
    c[ImGuiCol_WindowBg]={0.04f,0.04f,0.07f,0.98f}; c[ImGuiCol_ChildBg]={0.0f,0.0f,0.0f,0.0f};
    c[ImGuiCol_Border]={0.12f,0.12f,0.18f,1}; c[ImGuiCol_CheckMark]={0.49f,0.36f,1.0f,1};
    c[ImGuiCol_SliderGrab]={0.49f,0.36f,1.0f,1}; c[ImGuiCol_Separator]={0.15f,0.15f,0.22f,1};

    self.ready=YES;

    UIButton* b=[UIButton buttonWithType:UIButtonTypeSystem];
    b.frame=CGRectMake(pts.width-80,60,60,60);
    b.backgroundColor=[UIColor colorWithRed:0.49 green:0.36 blue:1.0 alpha:0.85];
    b.layer.cornerRadius=30; b.layer.borderWidth=2; b.layer.borderColor=[UIColor whiteColor].CGColor;
    [b setTitle:@"⚡" forState:UIControlStateNormal]; b.titleLabel.font=[UIFont systemFontOfSize:26];
    [b addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:b]; self.button=b;

    self.link=[CADisplayLink displayLinkWithTarget:self selector:@selector(render)];
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

-(void)toggle:(UIButton*)x{
    self.show=!self.show; self.host.hidden=!self.show; self.host.userInteractionEnabled=self.show;
    if(!self.show){ ImGui::GetIO().MouseDown[0]=false; ImGui::GetIO().MousePos={-FLT_MAX,-FLT_MAX}; }
}

-(void)render{
    if(!self.ready||!self.show)return;
    id<CAMetalDrawable> d=[self.ml nextDrawable]; if(!d)return;
    MTLRenderPassDescriptor* pd=[MTLRenderPassDescriptor renderPassDescriptor];
    pd.colorAttachments[0].texture=d.texture;
    pd.colorAttachments[0].loadAction=MTLLoadActionClear;
    pd.colorAttachments[0].storeAction=MTLStoreActionStore;
    pd.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);

    ImGui_ImplMetal_NewFrame(pd);
    ImGui::NewFrame();

    ImGui::SetNextWindowPos({0,0},ImGuiCond_Always);
    ImGui::SetNextWindowSize({440,360},ImGuiCond_Always);
    ImGui::Begin("##w",nullptr,ImGuiWindowFlags_NoResize|ImGuiWindowFlags_NoCollapse|ImGuiWindowFlags_NoMove|ImGuiWindowFlags_NoTitleBar);

    // логотип в сайдбаре (как "A" в круге на скрине)
    ImVec2 lp=ImGui::GetCursorScreenPos();
    ImGui::GetWindowDrawList()->AddCircleFilled(ImVec2(lp.x+50,lp.y+24),18,IM_COL32(124,92,255,255));
    ImGui::SetCursorScreenPos(ImVec2(lp.x+44,lp.y+14));
    ImGui::Text("A");
    ImGui::Spacing(); ImGui::Spacing();

    // сайдбар: 7 вкладок
    const char* tabs[]={"ESP","Chams","World","Ragebot","Misc","Configs","Inventory"};
    for(int i=0;i<7;i++){
        bool sel=(self.tab==i);
        ImVec2 cp=ImGui::GetCursorScreenPos();
        if(sel){
            ImGui::GetWindowDrawList()->AddRectFilled(cp,{cp.x+100,cp.y+30},IM_COL32(28,28,44,255),8);
            ImGui::GetWindowDrawList()->AddRectFilled(ImVec2(cp.x,cp.y+6),ImVec2(cp.x+3,cp.y+24),IM_COL32(124,92,255,255),2);
        }
        ImGui::SetCursorScreenPos(ImVec2(cp.x+12,cp.y+7));
        if(ImGui::Selectable(tabs[i],sel,0,{100,30})) self.tab=i;
        ImGui::Spacing();
    }
    ImGui::SameLine();

    // контент
    ImGui::BeginGroup();
    if(self.tab==0){
        Card("ESP Demo",200,150,[]{
            ToggleRow("Offscreen",&g_offscreen,"Shows enemies that are out of visibility");
        });
        ImGui::SameLine();
        Card("Preview",180,150,[]{
            ImGui::TextDisabled("ESP preview placeholder");
        });
    } else if(self.tab==4){
        Card("Combat & Movement",380,150,[]{
            ToggleRow("Wallbang",&g_wallbang,"Shoot through walls");
            ToggleRow("NoRecoil",&g_norecoil,"Zero recoil");
            ToggleRow("BunnyHop",&g_bunnyhop,"Auto jump");
        });
    } else {
        ImGui::TextDisabled("%s: coming soon", tabs[self.tab]);
    }
    ImGui::EndGroup();

    ImGui::End();
    ImGui::Render();
    id<MTLCommandBuffer> cb=[self.q commandBuffer];
    id<MTLRenderCommandEncoder> enc=[cb renderCommandEncoderWithDescriptor:pd];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(),cb,enc);
    [enc endEncoding]; [cb presentDrawable:d]; [cb commit];
}
@end
