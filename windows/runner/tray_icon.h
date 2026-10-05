#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>

// Notification-area icon, backing the same dev.tailtap/tray channel as the
// macOS status item in AppDelegate.swift.
class TrayIcon {
 public:
  TrayIcon(HWND window, flutter::BinaryMessenger* messenger);
  ~TrayIcon();

  TrayIcon(const TrayIcon&) = delete;
  TrayIcon& operator=(const TrayIcon&) = delete;

  // True while the app should keep running after its window is closed.
  bool keep_running() const { return keep_running_; }

  // True once the user asked to quit, so WM_CLOSE must not hide the window.
  bool quitting() const { return quitting_; }

  // Handles tray-related window messages, returning true when consumed.
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

  void HideMainWindow();
  void ShowMainWindow();

 private:
  void AddIcon();
  void UpdateIcon();
  void ShowMenu();
  void StopAllAndQuit();
  void Quit();

  static bool ReadKeepRunning();
  static void WriteKeepRunning(bool value);

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  NOTIFYICONDATAW icon_data_;
  bool icon_added_ = false;
  bool keep_running_ = true;
  bool quitting_ = false;
  int active_count_ = 0;
  std::wstring summary_;
};

#endif  // RUNNER_TRAY_ICON_H_
