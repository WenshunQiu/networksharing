#include "flutter_window.h"

#include <optional>
#include <shellapi.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kTrayCallbackMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayRestoreCommand = 1001;
constexpr UINT kTrayExitCommand = 1002;
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  NOTIFYICONDATA icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = GetHandle();
  icon.uID = kTrayIconId;
  icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  icon.uCallbackMessage = kTrayCallbackMessage;
  icon.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(icon.szTip, L"NetworkSharing");
  tray_icon_added_ = Shell_NotifyIcon(NIM_ADD, &icon) == TRUE;

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  if (tray_icon_added_) {
    NOTIFYICONDATA icon{};
    icon.cbSize = sizeof(icon);
    icon.hWnd = GetHandle();
    icon.uID = kTrayIconId;
    Shell_NotifyIcon(NIM_DELETE, &icon);
    tray_icon_added_ = false;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (message == kTrayCallbackMessage && lparam == WM_LBUTTONUP) {
    Show();
    SetForegroundWindow(hwnd);
    return 0;
  }
  if (message == kTrayCallbackMessage && lparam == WM_RBUTTONUP) {
    HMENU menu = CreatePopupMenu();
    AppendMenuW(menu, MF_STRING, kTrayRestoreCommand, L"Open NetworkSharing");
    AppendMenuW(menu, MF_STRING, kTrayExitCommand, L"Exit");
    POINT point{};
    GetCursorPos(&point);
    SetForegroundWindow(hwnd);
    const UINT command = TrackPopupMenu(
        menu, TPM_RETURNCMD | TPM_NONOTIFY, point.x, point.y, 0, hwnd, nullptr);
    DestroyMenu(menu);
    if (command == kTrayRestoreCommand) Show();
    if (command == kTrayExitCommand) {
      exit_requested_ = true;
      SendMessage(hwnd, WM_CLOSE, 0, 0);
    }
    return 0;
  }
  if (message == WM_SIZE && wparam == SIZE_MINIMIZED) {
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }
  if (message == WM_CLOSE && !exit_requested_) {
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
