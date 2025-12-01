#pragma once
#include <windows.h>
#include <stdint.h>   // ← 이거 추가하면 오류 해결됨!

extern "C" {
    __declspec(dllexport) void setStartup(uint8_t enable);
    __declspec(dllexport) uint8_t isStartupEnabled();
}
