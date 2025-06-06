package game

import "base:runtime"
import "core:fmt"
import "core:mem"
import w32 "core:sys/windows"

GlobalRunning: bool = false

WindowProc :: proc "stdcall" (
	hwnd: w32.HWND,
	msg: w32.UINT,
	wParam: w32.WPARAM,
	lParam: w32.LPARAM,
) -> w32.LRESULT {
	context = runtime.default_context()

	switch msg {
	case w32.WM_CLOSE:
		GlobalRunning = false
		w32.DestroyWindow(hwnd)
		return 0

	case w32.WM_DESTROY:
		w32.PostQuitMessage(0)
		return 0

	case:
		return w32.DefWindowProcW(hwnd, msg, wParam, lParam)
	}

}

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				for _, entry in track.allocation_map {
					fmt.eprintf("%v leaked %v bytes\n", entry.location, entry.size)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	hInstance := cast(w32.HANDLE)w32.GetModuleHandleW(nil)

	wc: w32.WNDCLASSW
	wc.style = w32.CS_HREDRAW | w32.CS_VREDRAW
	wc.lpfnWndProc = WindowProc
	wc.hInstance = hInstance
	wc.lpszClassName = w32.utf8_to_wstring("KRKBEngine")
	wc.hbrBackground = w32.GetSysColorBrush(w32.COLOR_WINDOW)

	if w32.RegisterClassW(&wc) == 0 {
		fmt.println("Failed to register class")
		return
	}

	hwnd := w32.CreateWindowExW(
		0,
		wc.lpszClassName,
		w32.utf8_to_wstring("KRKB_Engine"),
		w32.WS_OVERLAPPEDWINDOW,
		w32.CW_USEDEFAULT,
		w32.CW_USEDEFAULT,
		800,
		600,
		nil,
		nil,
		hInstance,
		nil,
	)

	if hwnd != nil {
		GlobalRunning = true

		for GlobalRunning {

			w32.ShowWindow(hwnd, w32.SW_SHOW)
			w32.UpdateWindow(hwnd)

			msg: w32.MSG

			for w32.PeekMessageW(&msg, nil, 0, 0, w32.PM_REMOVE) != false {
				if msg.message == w32.WM_QUIT {
					GlobalRunning = false
				}

				w32.TranslateMessage(&msg)
				w32.DispatchMessageW(&msg)
			}
		}

	}

}
