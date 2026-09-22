# Debug Session: Windows Shutdown Fast Fail

Status: [OPEN]
Session: windows-shutdown-fast-fail

## Symptom
Closing the Windows application shows: "快速异常检测失败。将不会调用异常处理程序，并且进程将立即终止。"

## Hypotheses
1. Async player/WebView disposal throws during shutdown.
2. Windows WebView2 or window plugin releases native resources twice.
3. Native fast-fail bypasses Dart zone handling; shutdown state must be logged before native teardown.
4. Recent login WebView, media player, or window manager shutdown paths trigger a native DLL conflict.

## Evidence

## Instrumentation

## Fix

## Verification
