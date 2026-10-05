#include "tray_icon.h"

#include <flutter/method_result_functions.h>
#include <strsafe.h>
#include <windows.h>

#include <string>
#include <utility>

#include "resource.h"

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kQuitMessage = WM_APP + 2;
constexpr UINT_PTR kQuitTimerId = 1;
constexpr UINT kQuitFallbackMs = 2000;

constexpr UINT kMenuOpen = 1;
constexpr UINT kMenuStopAll = 2;
constexpr UINT kMenuQuit = 3;

constexpr wchar_t kRunKey[] = L"Software\\TailTap";
constexpr wchar_t kKeepRunningValue[] = L"keepRunningInMenuBar";

std::wstring WideFromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int length = static_cast<int>(utf8.size());
  const int size =
      ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), length, nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), length, wide.data(), size);
  return wide;
}

}  // namespace

TrayIcon::TrayIcon(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window), keep_running_(ReadKeepRunning()) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "dev.tailtap/tray",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "getKeepRunning") {
          result->Success(flutter::EncodableValue(keep_running_));
          return;
        }
        if (method == "setKeepRunning") {
          const auto* value = std::get_if<bool>(call.arguments());
          if (value == nullptr) {
            result->Error("bad-arguments", "expected a bool");
            return;
          }
          keep_running_ = *value;
          WriteKeepRunning(keep_running_);
          result->Success();
          return;
        }
        if (method == "setStatus") {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments == nullptr) {
            result->Error("bad-arguments", "expected a map");
            return;
          }
          const auto count =
              arguments->find(flutter::EncodableValue("activeCount"));
          if (count != arguments->end()) {
            if (const auto* value = std::get_if<int32_t>(&count->second)) {
              active_count_ = *value;
            }
          }
          const auto summary =
              arguments->find(flutter::EncodableValue("summary"));
          if (summary != arguments->end()) {
            if (const auto* value = std::get_if<std::string>(&summary->second)) {
              summary_ = WideFromUtf8(*value);
            }
          }
          UpdateIcon();
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  AddIcon();
}

TrayIcon::~TrayIcon() {
  ::KillTimer(window_, kQuitTimerId);
  if (channel_) {
    // Destroying the channel does not unregister the handler.
    channel_->SetMethodCallHandler(nullptr);
  }
  if (icon_added_) {
    ::Shell_NotifyIconW(NIM_DELETE, &icon_data_);
    icon_added_ = false;
  }
}

bool TrayIcon::ReadKeepRunning() {
  DWORD value = 1;
  DWORD size = sizeof(value);
  DWORD type = 0;
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_QUERY_VALUE, &key) ==
      ERROR_SUCCESS) {
    if (::RegQueryValueExW(key, kKeepRunningValue, nullptr, &type,
                           reinterpret_cast<LPBYTE>(&value),
                           &size) != ERROR_SUCCESS ||
        type != REG_DWORD) {
      value = 1;
    }
    ::RegCloseKey(key);
  }
  return value != 0;
}

void TrayIcon::WriteKeepRunning(bool value) {
  HKEY key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr, &key,
                        nullptr) != ERROR_SUCCESS) {
    return;
  }
  const DWORD stored = value ? 1u : 0u;
  ::RegSetValueExW(key, kKeepRunningValue, 0, REG_DWORD,
                   reinterpret_cast<const BYTE*>(&stored), sizeof(stored));
  ::RegCloseKey(key);
}

void TrayIcon::AddIcon() {
  icon_data_ = {};
  icon_data_.cbSize = sizeof(NOTIFYICONDATAW);
  icon_data_.hWnd = window_;
  icon_data_.uID = 1;
  icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  icon_data_.uCallbackMessage = kTrayMessage;
  icon_data_.hIcon = static_cast<HICON>(::LoadImageW(
      ::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      ::GetSystemMetrics(SM_CXSMICON), ::GetSystemMetrics(SM_CYSMICON),
      LR_DEFAULTCOLOR));
  ::StringCchCopyW(icon_data_.szTip, ARRAYSIZE(icon_data_.szTip), L"TailTap");
  icon_added_ = ::Shell_NotifyIconW(NIM_ADD, &icon_data_) != FALSE;
}

void TrayIcon::UpdateIcon() {
  if (!icon_added_) {
    return;
  }
  std::wstring tip = L"TailTap";
  if (active_count_ > 0) {
    tip += L" · " + std::to_wstring(active_count_) + L" 个任务运行中";
  }
  ::StringCchCopyW(icon_data_.szTip, ARRAYSIZE(icon_data_.szTip),
                   tip.c_str());
  icon_data_.uFlags = NIF_TIP;
  ::Shell_NotifyIconW(NIM_MODIFY, &icon_data_);
}

void TrayIcon::ShowMenu() {
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  ::AppendMenuW(menu, MF_STRING, kMenuOpen, L"打开 TailTap");
  const std::wstring status = active_count_ == 0
                                  ? L"没有运行中的任务"
                                  : L"运行中：" + summary_;
  ::AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, status.c_str());
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING | (active_count_ > 0 ? MF_ENABLED : MF_GRAYED),
                kMenuStopAll, L"停止全部任务");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kMenuQuit, L"退出 TailTap");

  POINT cursor;
  ::GetCursorPos(&cursor);
  // TrackPopupMenu dismisses itself immediately unless its owner is the
  // foreground window. The owner is often hidden here, which blocks the normal
  // handoff, so attach to the current foreground thread first.
  const HWND foreground = ::GetForegroundWindow();
  const DWORD foreground_thread =
      foreground == nullptr ? 0 : ::GetWindowThreadProcessId(foreground, nullptr);
  const DWORD current_thread = ::GetCurrentThreadId();
  const bool attached =
      foreground_thread != 0 && foreground_thread != current_thread &&
      ::AttachThreadInput(current_thread, foreground_thread, TRUE) != FALSE;
  ::SetForegroundWindow(window_);
  if (attached) {
    ::AttachThreadInput(current_thread, foreground_thread, FALSE);
  }

  const UINT command =
      ::TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_BOTTOMALIGN,
                       cursor.x, cursor.y, 0, window_, nullptr);
  ::PostMessageW(window_, WM_NULL, 0, 0);
  ::DestroyMenu(menu);

  switch (command) {
    case kMenuOpen:
      ShowMainWindow();
      break;
    case kMenuStopAll:
    case kMenuQuit:
      StopAllAndQuit();
      break;
    default:
      break;
  }
}

void TrayIcon::StopAllAndQuit() {
  if (quitting_) {
    return;
  }
  const HWND window = window_;
  // Posting back to the window keeps the reply callback from touching a
  // TrayIcon that the window teardown may already have destroyed.
  channel_->InvokeMethod(
      "stopAll", nullptr,
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          [window](const flutter::EncodableValue*) {
            ::PostMessageW(window, kQuitMessage, 0, 0);
          },
          [window](const std::string&, const std::string&,
                   const flutter::EncodableValue*) {
            ::PostMessageW(window, kQuitMessage, 0, 0);
          },
          [window]() { ::PostMessageW(window, kQuitMessage, 0, 0); }));
  // Fallback for a missing or unresponsive Dart handler.
  ::SetTimer(window_, kQuitTimerId, kQuitFallbackMs, nullptr);
}

void TrayIcon::Quit() {
  if (quitting_) {
    return;
  }
  quitting_ = true;
  ::KillTimer(window_, kQuitTimerId);
  ::PostMessageW(window_, WM_CLOSE, 0, 0);
}

void TrayIcon::HideMainWindow() {
  ::ShowWindow(window_, SW_HIDE);
}

void TrayIcon::ShowMainWindow() {
  ::ShowWindow(window_, SW_SHOWNORMAL);
  ::SetForegroundWindow(window_);
}

bool TrayIcon::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kTrayMessage) {
    if (LOWORD(lparam) == WM_LBUTTONUP) {
      ShowMainWindow();
    } else if (LOWORD(lparam) == WM_RBUTTONUP) {
      ShowMenu();
    }
    return true;
  }
  if (message == kQuitMessage) {
    Quit();
    return true;
  }
  if (message == WM_TIMER && wparam == kQuitTimerId) {
    Quit();
    return true;
  }
  return false;
}
