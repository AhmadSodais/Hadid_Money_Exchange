#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <chrono>
#include <memory>
#include <optional>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Receives title bar color updates from Dart.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  struct TitleBarStyle {
    COLORREF caption;
    COLORREF text;
    BOOL dark;
  };

  // Last title bar style requested by Dart; re-applied after system theme
  // changes, which otherwise reset the frame to the OS colors.
  std::optional<TitleBarStyle> title_bar_style_;

  // Window style, placement and on-screen client area saved on entering full
  // screen, restored on exit.
  bool full_screen_ = false;
  LONG saved_style_ = 0;
  WINDOWPLACEMENT saved_placement_{sizeof(WINDOWPLACEMENT)};
  RECT saved_client_rect_{};

  // Window bounds sliding between the windowed and full-screen rects.
  struct BoundsAnimation {
    RECT from;
    RECT to;
    std::chrono::steady_clock::time_point start;
  };
  std::optional<BoundsAnimation> bounds_animation_;

  void ApplyTitleBarStyle();
  void SetFullScreen(bool enabled);
  void StartBoundsAnimation(const RECT& from, const RECT& to);
  void StepBoundsAnimation();
  void FinishBoundsAnimation();
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
