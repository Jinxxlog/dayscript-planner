#include "startup.h"
#include <string>
#include <windows.h>

static const wchar_t* RUN_KEY = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
static const wchar_t* APP_NAME = L"Dayscript";

void setStartup(uint8_t enable) {
    HKEY hKey;
    LONG result = RegOpenKeyEx(HKEY_CURRENT_USER, RUN_KEY, 0, KEY_WRITE, &hKey);

    if (result != ERROR_SUCCESS) return;

    if (enable) {
        wchar_t exePath[MAX_PATH];
        GetModuleFileName(NULL, exePath, MAX_PATH);
        RegSetValueEx(hKey, APP_NAME, 0, REG_SZ, (BYTE*)exePath,
            (DWORD)((wcslen(exePath) + 1) * sizeof(wchar_t)));
    } else {
        RegDeleteValue(hKey, APP_NAME);
    }

    RegCloseKey(hKey);
}

uint8_t isStartupEnabled() {
    HKEY hKey;
    LONG result = RegOpenKeyEx(HKEY_CURRENT_USER, RUN_KEY, 0, KEY_READ, &hKey);

    if (result != ERROR_SUCCESS) return 0;

    DWORD type = REG_SZ;
    wchar_t buffer[MAX_PATH];
    DWORD bufferSize = sizeof(buffer);

    result = RegGetValue(hKey, NULL, APP_NAME, RRF_RT_REG_SZ, &type, buffer, &bufferSize);

    RegCloseKey(hKey);

    return (result == ERROR_SUCCESS) ? 1 : 0;
}
