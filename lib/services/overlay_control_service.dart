import 'dart:io';
import 'dart:async';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:win32/win32.dart';

/// 💡 오버레이 제어 전용 서비스
class OverlayControlService {
  static Timer? _focusWatcher;

  /// Flutter 쪽에서만 사용하는 "논리적" 투명도 값 (0.3 ~ 1.0 정도 권장)
  static double _currentOpacity = 1.0;

  static double get currentOpacity => _currentOpacity;

  // ─────────────────────────────────────────────
  // ✅ 초기화
  // ─────────────────────────────────────────────
  static Future<void> init() async {
    try {
      await windowManager.ensureInitialized();
    } catch (e) {
      debugPrint("⚠️ windowManager 초기화 오류: $e");
    }
  }

  // ─────────────────────────────────────────────
  // ⭐ 핵심: "배경 느낌" 투명도 논리값만 저장
  static Future<void> setBackgroundOpacity(double opacity) async {
    // 최소/최대값 클램프 (너가 원하는 범위로 조정 가능)
    if (opacity < 0.3) opacity = 0.3;
    if (opacity > 1.0) opacity = 1.0;

    _currentOpacity = opacity;
    debugPrint("🎛️ [배경 논리값] opacity=${opacity.toStringAsFixed(2)}");

    // ✅ 여기서 실제 윈도우 투명도 적용
    try {
      await windowManager.setOpacity(opacity);
    } catch (e) {
      debugPrint("⚠️ setOpacity 실패: $e");
    }
  }


  // ─────────────────────────────────────────────
  // ✅ 오버레이 모드 진입
  // ─────────────────────────────────────────────
  static Future<void> enterOverlayMode() async {
    try {
      debugPrint("🪟 오버레이 모드 진입 중...");

      await windowManager.waitUntilReadyToShow(null, () async {
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setSkipTaskbar(true);
        await windowManager.setHasShadow(false);
        await windowManager.setResizable(false);
        await windowManager.setBackgroundColor(const Color(0x00000000));
        await windowManager.focus();

        Timer(const Duration(milliseconds: 300), () async {
          await windowManager.setAsFrameless();

          if (!Platform.isWindows) {
            await windowManager.setMovable(false);
          }

          if (Platform.isWindows) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await Future.delayed(const Duration(milliseconds: 400));
              await moveBelowAllWindows();

              // 🔹 "배경 느낌"은 Flutter 쪽에서 _currentOpacity로 처리
              _startFocusWatcher();
            });
          }
        });
      });

      debugPrint("✅ 오버레이 모드 전환 완료");
    } catch (e) {
      debugPrint("❌ 오버레이 모드 전환 실패: $e");
    }
  }

  // ─────────────────────────────────────────────
  // ✅ 오버레이 포커스 감시 (포커스 잃으면 자동 아래로)
  // ─────────────────────────────────────────────
  static void _startFocusWatcher() {
    _focusWatcher?.cancel();
    _focusWatcher = Timer.periodic(const Duration(seconds: 1), (_) async {
      final isFocused = await windowManager.isFocused();
      if (!isFocused) {
        await moveBelowAllWindows();
      }
    });
  }

  // ─────────────────────────────────────────────
  // ✅ 일반 모드 복귀
  // ─────────────────────────────────────────────
  static Future<void> exitOverlayMode() async {
    try {
      debugPrint("↩️ 일반 모드 복귀 중...");

      _focusWatcher?.cancel();

      await windowManager.setAlwaysOnTop(false);
      await windowManager.setSkipTaskbar(false);
      await windowManager.setHasShadow(true);
      await windowManager.setResizable(true);
      await windowManager.setBackgroundColor(const Color(0xFFFFFFFF));

      // ✅ 프레임 복원에 해당하는 부분
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);

      Timer(const Duration(milliseconds: 200), () async {
        // ✅ Windows도 이동 가능하게 보장
        await windowManager.setMovable(true);
      });

      await windowManager.focus();

      debugPrint("✅ 일반 모드 복귀 완료");
    } catch (e) {
      debugPrint("❌ 일반 모드 복귀 실패: $e");
    }
  }

  
  // ─────────────────────────────────────────────
  // ✅ 창을 바탕화면 바로 위로 이동 (AlwaysOnBottom 대체)
  // ─────────────────────────────────────────────
  static Future<void> moveBelowAllWindows() async {
    try {
      const windowTitle = 'DayScript';
      final titlePtr = windowTitle.toNativeUtf16();

      // NULL 포인터
      final nullPtr = ffi.Pointer<Utf16>.fromAddress(0);
      final hwnd = FindWindow(nullPtr, titlePtr);

      calloc.free(titlePtr);

      if (hwnd == 0) {
        debugPrint("⚠️ HWND 탐색 실패: 창 타이틀 불일치 가능");
        return;
      }

      SetWindowPos(
        hwnd,
        HWND_BOTTOM,
        0,
        0,
        0,
        0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE,
      );
      debugPrint("🪟 창을 바탕화면 바로 위로 이동 완료 (HWND=$hwnd)");
    } catch (e) {
      debugPrint("❌ moveBelowAllWindows 실패: $e");
    }
  }
}
