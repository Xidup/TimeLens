// Windows 原生悬浮计时窗
//
// 独立的 C++ Win32 程序，不依赖 Flutter 引擎。
// - 无边框、始终置顶、可拖动
// - mm:ss 格式显示当前应用使用时长
// - 通过 HTTP 轮询 ActivityWatch API
//
// 编译 (MSVC):
//   cl /EHsc /O2 overlay_native.cpp /link user32.lib gdi32.lib winhttp.lib

#ifndef UNICODE
#define UNICODE
#endif

#include <windows.h>
#include <winhttp.h>
#include <string>
#include <sstream>
#include <chrono>
#include <thread>
#include <atomic>
#include <map>

#pragma comment(lib, "winhttp.lib")

// ==================== 配置 ====================
constexpr int TIMER_WIDTH = 200;
constexpr int TIMER_HEIGHT = 55;
constexpr int POLL_INTERVAL_MS = 3000;
constexpr int RED_THRESHOLD_MINUTES = 30;

constexpr COLORREF COLOR_GREEN_BG = RGB(0x2E, 0x7D, 0x32);
constexpr COLORREF COLOR_RED_BG = RGB(0xC6, 0x28, 0x28);
constexpr COLORREF COLOR_WHITE = RGB(255, 255, 255);
constexpr COLORREF COLOR_WHITE70 = RGB(179, 179, 179);

// ==================== HTTP 客户端 ====================
class HttpClient {
    HINTERNET hSession = nullptr;
    HINTERNET hConnect = nullptr;

public:
    bool init() {
        hSession = WinHttpOpen(L"TimeLens/1.0",
            WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
        if (!hSession) return false;

        hConnect = WinHttpConnect(hSession, L"localhost", 5600, 0);
        return hConnect != nullptr;
    }

    std::string get(const std::wstring& path) {
        HINTERNET hRequest = WinHttpOpenRequest(hConnect, L"GET", path.c_str(),
            nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
        if (!hRequest) return "";

        WinHttpSendRequest(hRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
            WINHTTP_NO_REQUEST_DATA, 0, 0, 0);
        WinHttpReceiveResponse(hRequest, nullptr);

        std::string result;
        DWORD bytesRead = 0;
        char buffer[4096];
        while (WinHttpReadData(hRequest, buffer, sizeof(buffer), &bytesRead) && bytesRead > 0) {
            result.append(buffer, bytesRead);
        }
        WinHttpCloseHandle(hRequest);
        return result;
    }

    ~HttpClient() {
        if (hConnect) WinHttpCloseHandle(hConnect);
        if (hSession) WinHttpCloseHandle(hSession);
    }
};

// ==================== JSON 简易解析 ====================
std::string jsonGetString(const std::string& json, const std::string& key) {
    std::string search = "\"" + key + "\": \"";
    size_t pos = json.find(search);
    if (pos == std::string::npos) return "";
    pos += search.size();
    size_t end = json.find("\"", pos);
    return json.substr(pos, end - pos);
}

double jsonGetNumber(const std::string& json, const std::string& key) {
    std::string search = "\"" + key + "\": ";
    size_t pos = json.find(search);
    if (pos == std::string::npos) return 0;
    pos += search.size();
    size_t end = json.find_first_of(",}\n", pos);
    return std::stod(json.substr(pos, end - pos));
}

// ==================== 数据模型 ====================
struct AppUsage {
    std::string name;
    double todaySeconds = 0;
    std::chrono::steady_clock::time_point lastUpdate;
};

// ==================== 全局状态 ====================
std::atomic<bool> g_running{true};
AppUsage g_currentApp;
HttpClient g_http;
HWND g_hwnd = nullptr;
HFONT g_font = nullptr;
HFONT g_fontSmall = nullptr;

// ==================== 轮询 ActivityWatch ====================
void pollActivityWatch() {
    try {
        // 1. 获取 buckets 列表
        auto bucketsJson = g_http.get(L"/api/0/buckets/");
        if (bucketsJson.empty()) return;

        // 2. 找到 aw-watcher-window bucket ID
        std::string bucketId;
        size_t pos = bucketsJson.find("aw-watcher-window_");
        if (pos == std::string::npos) return;
        size_t idStart = pos;
        size_t idEnd = bucketsJson.find("\"", idStart);
        bucketId = bucketsJson.substr(idStart, idEnd - idStart);

        // 3. 获取今日事件
        auto eventsJson = g_http.get(
            std::wstring(L"/api/0/buckets/") +
            std::wstring(bucketId.begin(), bucketId.end()) +
            L"/events?limit=500");

        // 4. 解析最新事件
        size_t lastDataPos = eventsJson.rfind("\"data\"");
        if (lastDataPos == std::string::npos) return;

        std::string appName = "Unknown";
        size_t appPos = eventsJson.find("\"app\": \"", lastDataPos);
        if (appPos != std::string::npos) {
            appPos += 8;
            size_t appEnd = eventsJson.find("\"", appPos);
            appName = eventsJson.substr(appPos, appEnd - appPos);
        }

        // 5. 计算今日累计时长（简化：累加所有事件的 duration）
        double totalDuration = 0;
        size_t durPos = 0;
        std::string durKey = "\"duration\": ";
        while ((durPos = eventsJson.find(durKey, durPos)) != std::string::npos) {
            durPos += durKey.size();
            size_t durEnd = eventsJson.find_first_of(",}\n", durPos);
            totalDuration += std::stod(eventsJson.substr(durPos, durEnd - durPos));
            durPos = durEnd;
        }

        g_currentApp.name = appName;
        g_currentApp.todaySeconds = totalDuration;
    } catch (...) {
        // 静默处理
    }
}

// ==================== 窗口过程 ====================
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_CREATE: {
        // 创建字体
        g_font = CreateFontW(28, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, FIXED_PITCH | FF_MODERN, L"Consolas");
        g_fontSmall = CreateFontW(11, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");

        // 圆角窗口
        SetWindowRgn(hwnd, CreateRoundRectRgn(0, 0, TIMER_WIDTH + 1, TIMER_HEIGHT + 1, 12, 12), TRUE);

        // 启动定时器
        SetTimer(hwnd, 1, POLL_INTERVAL_MS, nullptr);
        SetTimer(hwnd, 2, 1000, nullptr); // 每秒重绘
        pollActivityWatch();
        break;
    }

    case WM_TIMER:
        if (wParam == 1) pollActivityWatch();
        InvalidateRect(hwnd, nullptr, TRUE);
        break;

    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);

        RECT rect;
        GetClientRect(hwnd, &rect);

        // 背景色
        bool isGreen = (g_currentApp.todaySeconds < RED_THRESHOLD_MINUTES * 60);
        HBRUSH bgBrush = CreateSolidBrush(isGreen ? COLOR_GREEN_BG : COLOR_RED_BG);
        FillRect(hdc, &rect, bgBrush);
        DeleteObject(bgBrush);

        SetBkMode(hdc, TRANSPARENT);

        // 应用名
        if (!g_currentApp.name.empty()) {
            SelectObject(hdc, g_fontSmall);
            SetTextColor(hdc, COLOR_WHITE70);
            std::wstring wApp(g_currentApp.name.begin(), g_currentApp.name.end());
            RECT appRect = {12, 4, rect.right - 12, 20};
            DrawTextW(hdc, wApp.c_str(), -1, &appRect, DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS);
        }

        // mm:ss 计时
        int totalSec = static_cast<int>(g_currentApp.todaySeconds);
        int minutes = (totalSec / 60) % 60;
        int seconds = totalSec % 60;
        wchar_t timeStr[16];
        swprintf_s(timeStr, L"%02d:%02d", minutes, seconds);

        SelectObject(hdc, g_font);
        SetTextColor(hdc, COLOR_WHITE);
        RECT timeRect = {12, 14, rect.right - 12, rect.bottom - 4};
        DrawTextW(hdc, timeStr, -1, &timeRect, DT_LEFT | DT_SINGLELINE);

        EndPaint(hwnd, &ps);
        break;
    }

    case WM_LBUTTONDOWN:
        // 拖动窗口
        SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
        break;

    case WM_RBUTTONUP:
        // 右键退出
        DestroyWindow(hwnd);
        break;

    case WM_DESTROY:
        g_running = false;
        if (g_font) DeleteObject(g_font);
        if (g_fontSmall) DeleteObject(g_fontSmall);
        PostQuitMessage(0);
        break;

    default:
        return DefWindowProc(hwnd, msg, wParam, lParam);
    }
    return 0;
}

// ==================== 入口 ====================
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE, LPSTR, int nCmdShow) {
    // 初始化 HTTP
    if (!g_http.init()) {
        MessageBoxW(nullptr, L"无法初始化 HTTP 客户端", L"时光镜", MB_ICONERROR);
        return 1;
    }

    // 注册窗口类
    const wchar_t CLASS_NAME[] = L"TimeLensOverlay";
    WNDCLASSW wc = {};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = CLASS_NAME;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    RegisterClassW(&wc);

    // 创建窗口：无边框，置顶，工具窗口
    HWND hwnd = CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_LAYERED,
        CLASS_NAME, L"时光镜",
        WS_POPUP,
        CW_USEDEFAULT, CW_USEDEFAULT,
        TIMER_WIDTH, TIMER_HEIGHT,
        nullptr, nullptr, hInstance, nullptr);

    if (!hwnd) return 1;

    // 半透明拖动
    SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);

    ShowWindow(hwnd, nCmdShow);
    UpdateWindow(hwnd);

    // 消息循环
    MSG msg = {};
    while (GetMessage(&msg, nullptr, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    return 0;
}
