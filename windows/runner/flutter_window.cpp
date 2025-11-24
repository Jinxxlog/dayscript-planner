#include "flutter_window.h"

#include <optional>
#include <windows.h>   // ★ 추가: 투명 제어 Win32 API
#include "flutter/generated_plugin_registrant.h"
#include <flutter/method_channel.h>   // ★ 추가
#include <flutter/standard_method_codec.h> // ★ 추가

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);

  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();


  // ─────────────────────────────────────────────
  // ★ 추가: Flutter → Windows 투명도 제어 MethodChannel
  // ─────────────────────────────────────────────
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "dayscript/overlay",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
    [this](const flutter::MethodCall<flutter::EncodableValue>& call,
           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) 
    {
      HWND hwnd = GetHandle();  // 현재 Flutter Window 핸들

      if (call.method_name() == "setTransparent") {
        int alpha = -1;

        if (call.arguments()) {
          auto& args = std::get<flutter::EncodableMap>(*call.arguments());
          alpha = std::get<int>(args.at(flutter::EncodableValue("alpha")));
        }

        if (alpha >= 0 && alpha <= 255) {
          // WS_EX_LAYERED 적용
          LONG style = GetWindowLong(hwnd, GWL_EXSTYLE);
          SetWindowLong(hwnd, GWL_EXSTYLE, style | WS_EX_LAYERED);

          // 투명도 조절
          SetLayeredWindowAttributes(hwnd, 0, (BYTE)alpha, LWA_ALPHA);

          result->Success();
        } else {
          result->Error("INVALID_ALPHA", "Alpha must be 0~255");
        }
        return;
      }

      result->NotImplemented();
    }
  );

  // ─────────────────────────────────────────────

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {

  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
