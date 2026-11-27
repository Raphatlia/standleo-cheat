#pragma once

namespace hooks {
    // Инициализация (вызвать один раз)
    void init();
    
    // Вызывать каждый кадр из render()
    void update();
    
    // Состояния из GUI (extern чтобы видеть Cheat.mm)
    extern bool g_bunnyhop;
    extern bool g_norecoil;
    extern bool g_wallbang;
}
