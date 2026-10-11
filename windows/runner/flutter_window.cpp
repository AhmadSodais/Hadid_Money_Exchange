#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <uxtheme.h>
#include <winbio.h>

#include <cmath>
#include <mutex>
#include <optional>
#include <thread>

#include "flutter/generated_plugin_registrant.h"

// Redefined in case the Windows SDK is older than 10.0.22000.0.
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif
#ifndef DWMWA_TEXT_COLOR
#define DWMWA_TEXT_COLOR 36
#endif

namespace {

// Converts a Dart ARGB color int into a Win32 COLORREF (0x00BBGGRR).
COLORREF ArgbToColorRef(int64_t argb) {
  const auto r = static_cast<BYTE>((argb >> 16) & 0xFF);
  const auto g = static_cast<BYTE>((argb >> 8) & 0xFF);
  const auto b = static_cast<BYTE>(argb & 0xFF);
  return RGB(r, g, b);
}

// Windows Hello does not report whether the sensor is a fingerprint reader
// or a camera, so the biometric framework is queried directly.
bool HasBiometricFactor(WINBIO_BIOMETRIC_TYPE factor) {
  WINBIO_UNIT_SCHEMA* schema = nullptr;
  SIZE_T count = 0;
  const HRESULT hr = WinBioEnumBiometricUnits(factor, &schema, &count);
  if (SUCCEEDED(hr) && schema != nullptr) {
    WinBioFree(schema);
  }
  return SUCCEEDED(hr) && count > 0;
}

struct BiometricProbe {
  std::mutex mu;
  bool ready = false;
  flutter::EncodableList kinds;
};

BiometricProbe& BiometricProbeState() {
  static BiometricProbe probe;
  return probe;
}

void StartBiometricProbe() {
  static std::once_flag once;
  std::call_once(once, [] {
    std::thread([] {
      const HRESULT com = ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);
      flutter::EncodableList kinds;
      if (HasBiometricFactor(WINBIO_TYPE_FINGERPRINT)) {
        kinds.emplace_back(flutter::EncodableValue("fingerprint"));
      }
      if (HasBiometricFactor(WINBIO_TYPE_FACIAL_FEATURES)) {
        kinds.emplace_back(flutter::EncodableValue("face"));
      }
      if (SUCCEEDED(com)) {
        ::CoUninitialize();
      }
      auto& probe = BiometricProbeState();
      std::lock_guard<std::mutex> lock(probe.mu);
      probe.kinds = std::move(kinds);
      probe.ready = true;
    }).detach();
  });
}

std::optional<int64_t> GetIntArg(const flutter::EncodableMap& args,
                                 const char* key) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return std::nullopt;
  }
  if (const auto* v = std::get_if<int32_t>(&it->second)) {
    return *v;
  }
  if (const auto* v = std::get_if<int64_t>(&it->second)) {
    return *v;
  }
  return std::nullopt;
}

// Hides the app icon and title text in the title bar. The window title is
// kept so the taskbar and Alt+Tab still show the app name.
void HideTitleBarIconAndCaption(HWND hwnd) {
  WTA_OPTIONS options{};
  options.dwFlags = WTNCA_NODRAWCAPTION | WTNCA_NODRAWICON;
  options.dwMask = WTNCA_NODRAWCAPTION | WTNCA_NODRAWICON;
  SetWindowThemeAttribute(hwnd, WTA_NONCLIENT, &options, sizeof(options));
}

constexpr UINT_PTR kBoundsAnimationTimer = 0xF5C1;
constexpr double kBoundsAnimationMs = 260.0;

RECT ClientRectOnScreen(HWND hwnd) {
  RECT client{};
  GetClientRect(hwnd, &client);
  POINT top_left{client.left, client.top};
  POINT bottom_right{client.right, client.bottom};
  ClientToScreen(hwnd, &top_left);
  ClientToScreen(hwnd, &bottom_right);
  return RECT{top_left.x, top_left.y, bottom_right.x, bottom_right.y};
}

void SetBounds(HWND hwnd, const RECT& r, UINT extra_flags) {
  SetWindowPos(hwnd, HWND_TOP, r.left, r.top, r.right - r.left,
               r.bottom - r.top,
               SWP_NOOWNERZORDER | SWP_NOACTIVATE | extra_flags);
}

LONG Lerp(LONG a, LONG b, double t) {
  return a + static_cast<LONG>(std::lround((b - a) * t));
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  HideTitleBarIconAndCaption(GetHandle());

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

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "app/window",
          &flutter::StandardMethodCodec::GetInstance());
  StartBiometricProbe();
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "biometricKinds") {
          StartBiometricProbe();
          auto& probe = BiometricProbeState();
          std::lock_guard<std::mutex> lock(probe.mu);
          if (!probe.ready) {
            result->Success();
            return;
          }
          result->Success(flutter::EncodableValue(probe.kinds));
          return;
        }
        if (call.method_name() == "isFullScreen") {
          result->Success(flutter::EncodableValue(full_screen_));
          return;
        }
        if (call.method_name() == "setFullScreen") {
          const auto* enabled = std::get_if<bool>(call.arguments());
          if (!enabled) {
            result->Error("bad_args", "Expected a bool");
            return;
          }
          SetFullScreen(*enabled);
          result->Success(flutter::EncodableValue(full_screen_));
          return;
        }
        if (call.method_name() != "setTitleBarColor") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) {
          result->Error("bad_args", "Expected a map");
          return;
        }
        auto background = GetIntArg(*args, "background");
        auto foreground = GetIntArg(*args, "foreground");
        auto dark_it = args->find(flutter::EncodableValue("dark"));
        const bool* dark = dark_it == args->end()
                               ? nullptr
                               : std::get_if<bool>(&dark_it->second);
        if (!background || !foreground || !dark) {
          result->Error("bad_args", "Missing background/foreground/dark");
          return;
        }
        title_bar_style_ = TitleBarStyle{ArgbToColorRef(*background),
                                         ArgbToColorRef(*foreground),
                                         *dark ? TRUE : FALSE};
        ApplyTitleBarStyle();
        result->Success();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  bounds_animation_.reset();
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::ApplyTitleBarStyle() {
  HWND hwnd = GetHandle();
  if (!hwnd || !title_bar_style_) {
    return;
  }
  // Dark mode controls the min/max/close glyphs; caption/text colors need
  // Windows 11 and are silently ignored on Windows 10.
  DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE,
                        &title_bar_style_->dark,
                        sizeof(title_bar_style_->dark));
  DwmSetWindowAttribute(hwnd, DWMWA_CAPTION_COLOR, &title_bar_style_->caption,
                        sizeof(title_bar_style_->caption));
  DwmSetWindowAttribute(hwnd, DWMWA_TEXT_COLOR, &title_bar_style_->text,
                        sizeof(title_bar_style_->text));
}

void FlutterWindow::SetFullScreen(bool enabled) {
  HWND hwnd = GetHandle();
  if (!hwnd || enabled == full_screen_) {
    return;
  }
  FinishBoundsAnimation();

  if (enabled) {
    MONITORINFO monitor{sizeof(MONITORINFO)};
    if (!GetWindowPlacement(hwnd, &saved_placement_) ||
        !GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                        &monitor)) {
      return;
    }
    saved_style_ = GetWindowLong(hwnd, GWL_STYLE);
    saved_client_rect_ = ClientRectOnScreen(hwnd);
    // Drop the frame around the current client area so the content stays
    // put, then grow the borderless window out to the monitor edges.
    SetWindowLong(hwnd, GWL_STYLE, saved_style_ & ~WS_OVERLAPPEDWINDOW);
    SetBounds(hwnd, saved_client_rect_, SWP_FRAMECHANGED | SWP_SHOWWINDOW);
    full_screen_ = true;
    StartBoundsAnimation(saved_client_rect_, monitor.rcMonitor);
  } else {
    RECT current{};
    GetWindowRect(hwnd, &current);
    full_screen_ = false;
    StartBoundsAnimation(current, saved_client_rect_);
  }
}

void FlutterWindow::StartBoundsAnimation(const RECT& from, const RECT& to) {
  bounds_animation_ =
      BoundsAnimation{from, to, std::chrono::steady_clock::now()};
  SetTimer(GetHandle(), kBoundsAnimationTimer, USER_TIMER_MINIMUM, nullptr);
}

void FlutterWindow::StepBoundsAnimation() {
  if (!bounds_animation_) {
    return;
  }
  const double elapsed = std::chrono::duration<double, std::milli>(
                             std::chrono::steady_clock::now() -
                             bounds_animation_->start)
                             .count();
  const double t = elapsed / kBoundsAnimationMs;
  if (t >= 1.0) {
    FinishBoundsAnimation();
    return;
  }
  const double eased = 1.0 - std::pow(1.0 - t, 3.0);
  const RECT& from = bounds_animation_->from;
  const RECT& to = bounds_animation_->to;
  SetBounds(GetHandle(),
            RECT{Lerp(from.left, to.left, eased), Lerp(from.top, to.top, eased),
                 Lerp(from.right, to.right, eased),
                 Lerp(from.bottom, to.bottom, eased)},
            0);
}

void FlutterWindow::FinishBoundsAnimation() {
  if (!bounds_animation_) {
    return;
  }
  HWND hwnd = GetHandle();
  KillTimer(hwnd, kBoundsAnimationTimer);
  const RECT to = bounds_animation_->to;
  bounds_animation_.reset();

  if (full_screen_) {
    SetBounds(hwnd, to, 0);
    return;
  }
  // Back at the original client area: put the frame back around it.
  SetWindowLong(hwnd, GWL_STYLE, saved_style_);
  SetWindowPlacement(hwnd, &saved_placement_);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                   SWP_FRAMECHANGED);
  ApplyTitleBarStyle();
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

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_TIMER:
      if (wparam == kBoundsAnimationTimer) {
        StepBoundsAnimation();
        return 0;
      }
      break;
    case WM_DWMCOLORIZATIONCOLORCHANGED: {
      LRESULT result =
          Win32Window::MessageHandler(hwnd, message, wparam, lparam);
      ApplyTitleBarStyle();
      return result;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
