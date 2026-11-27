#import "Hooks.hpp"
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <cstring>

namespace hooks {
    bool g_bunnyhop = false;
    bool g_norecoil = false;
    bool g_wallbang = false;
    
    static uintptr_t g_base = 0;
    static bool g_ready = false;
    
    // Адреса из dump.cs (RVA)
    namespace off {
        // PlayerControls.GetInputs() -> возвращает PlayerInputs*
        // RVA из script_addresses.txt
        constexpr uintptr_t get_inputs = 0x1F07934;
        
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
        
        // Делаем страницу читаемой/записываемой/исполняемой
        vm_protect(mach_task_self(), page_start, page_size, false,
                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
        
        // Сохраняем оригинальные 16 байт
        uint8_t orig_bytes[32];
        memcpy(orig_bytes, (void*)target, 16);
        
        // Пишем hook: ldr x16, [pc, #8]; br x16; .quad hook_addr
        uint32_t* code = (uint32_t*)target;
        code[0] = 0x58000050;  // ldr x16, [pc, #8]
        code[1] = 0xD61F0200;  // br x16
        *(uintptr_t*)(code + 2) = hook;
        
        // Создаём trampoline (оригинал + переход обратно)
        uintptr_t tramp = (uintptr_t)malloc(64);
        memcpy((void*)tramp, orig_bytes, 16);
        code = (uint32_t*)(tramp + 16);
        code[0] = 0x58000050;
        code[1] = 0xD61F0200;
        *(uintptr_t*)(code + 2) = target + 16;
        
        if (original) *original = tramp;
        
        // Возвращаем защиту
        vm_protect(mach_task_self(), page_start, page_size, false,
                   VM_PROT_READ | VM_PROT_EXECUTE);
        
        // Чищим кэш инструкций
        sys_icache_invalidate((void*)target, 16);
        sys_icache_invalidate((void*)tramp, 32);
        
        return true;
    }
    
    // Тип функции GetInputs
    typedef void* (*GetInputs_t)(void* player_controls);
    static GetInputs_t orig_get_inputs = nullptr;
    static void* last_player_inputs = nullptr;
    
    // Хук GetInputs
    static void* hk_get_inputs(void* player_controls) {
        void* ret = orig_get_inputs(player_controls);
        if (ret) {
            last_player_inputs = ret;
            // Если bunnyhop включён — форсим прыжок
            if (g_bunnyhop) {
                *(bool*)((uintptr_t)ret + off::is_to_jump) = true;
            }
        }
        return ret;
    }
    
    void init() {
        if (g_ready) return;
        g_base = find_base();
        g_ready = (g_base != 0);
        
        if (g_ready) {
            uintptr_t target = g_base + off::get_inputs;
            inline_hook(target, (uintptr_t)hk_get_inputs, (uintptr_t*)&orig_get_inputs);
        }
    }
    
    void update() {
        if (!g_ready) return;
        
        // NoRecoil — патчим _recoilMult в последнем GunController
        // (нужно найти указатель на GunController через PlayerController)
        // Пока заглушка — нужен адрес GunController
    }
}
