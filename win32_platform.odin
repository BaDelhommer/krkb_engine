package game

import "base:runtime"
import "core:fmt"
import "core:mem"
import w32 "core:sys/windows"

game_offscreen_buffer :: struct {
	info:            w32.BITMAPINFO,
	memory:          []u32,
	width:           i32,
	height:          i32,
	bytes_per_pixel: i32,
	pitch:           i32,
}

window_dimension :: struct {
	width, height: u32,
}

GlobalBackBuffer: game_offscreen_buffer
GlobalRunning: bool = false

TileMap := [9][9]u32 {
	{1, 1, 1, 1, 1, 1, 1, 1, 1},
	{1, 0, 0, 0, 0, 0, 0, 0, 1},
	{1, 0, 0, 0, 0, 0, 0, 0, 1},
	{1, 0, 0, 0, 0, 0, 0, 0, 1},
	{1, 0, 0, 0, 0, 0, 0, 0, 1},
	{1, 0, 0, 0, 0, 0, 0, 0, 1},
	{1, 0, 0, 0, 0, 0, 0, 0, 1},
	{1, 0, 0, 0, 0, 0, 0, 0, 1},
	{1, 1, 1, 1, 1, 1, 1, 1, 1},
}

InitTileMap :: proc(TileMap: [9][9]u32, DeviceContext: w32.HDC) {
	for y in 0 ..< len(TileMap) {
		for x in 0 ..< len(TileMap[y]) {
			if TileMap[x][y] == 1 {
				Tile: w32.RECT
				Tile.left = i32(x * 16)
				Tile.right = i32(x * 16 + 16)
				Tile.top = i32(y * 16)
				Tile.bottom = i32(y * 16 + 16)
				w32.FillRect(DeviceContext, &Tile, w32.HBRUSH(w32.GetStockObject(w32.WHITE_BRUSH)))
			}
		}
	}
}

InitBackBuffer :: proc(Buffer: ^game_offscreen_buffer, width, height: i32) {

	if Buffer.memory != nil {
		FreeBackBuffer(Buffer)
	}

	Buffer.width = width
	Buffer.height = height
	Buffer.bytes_per_pixel = 4
	Buffer.pitch = width * GlobalBackBuffer.bytes_per_pixel

	Buffer.info.bmiHeader.biSize = size_of(Buffer.info.bmiHeader)
	Buffer.info.bmiHeader.biWidth = Buffer.width
	Buffer.info.bmiHeader.biHeight = Buffer.height
	Buffer.info.bmiHeader.biPlanes = 1
	Buffer.info.bmiHeader.biBitCount = 32
	Buffer.info.bmiHeader.biCompression = w32.BI_RGB

	total_pixels := width * height
	Buffer.memory = make([]u32, total_pixels)
}

FreeBackBuffer :: proc(Buffer: ^game_offscreen_buffer) {
	delete(Buffer.memory)
}

RenderWeirdGradient :: proc(offset_x, offset_y: i32) {
	for y in 0 ..< GlobalBackBuffer.height {
		for x in 0 ..< GlobalBackBuffer.width {
			index := y * GlobalBackBuffer.width + x

			blue := u8(x + offset_x)
			green := u8(y + offset_y)
			red := u8(128)
			alpha := u8(255)

			pixel := (u32(alpha) << 24) | (u32(red) << 16) | (u32(green) << 8) | u32(blue)

			GlobalBackBuffer.memory[index] = pixel
		}
	}
}

DisplayBufferInWindow :: proc(
	Buffer: ^game_offscreen_buffer,
	DC: w32.HDC,
	WindowWidth, WindowHeight: u32,
) {
	w32.StretchDIBits(
		DC,
		0,
		0,
		i32(WindowWidth),
		i32(WindowHeight),
		0,
		0,
		Buffer.width,
		Buffer.height,
		raw_data(Buffer.memory),
		&Buffer.info,
		w32.DIB_RGB_COLORS,
		w32.SRCCOPY,
	)
}

GetWindowDimension :: proc(hwnd: w32.HWND) -> window_dimension {
	Result: window_dimension

	ClientRect: w32.RECT
	w32.GetClientRect(hwnd, &ClientRect)
	Result.width = u32(ClientRect.right - ClientRect.left)
	Result.height = u32(ClientRect.bottom - ClientRect.top)

	return Result
}

WindowProc :: proc "stdcall" (
	hwnd: w32.HWND,
	msg: w32.UINT,
	wParam: w32.WPARAM,
	lParam: w32.LPARAM,
) -> w32.LRESULT {
	context = runtime.default_context()

	switch msg {
	case w32.WM_SIZE:
		w32.InvalidateRect(hwnd, nil, true)
		return 0

	case w32.WM_CLOSE:
		GlobalRunning = false
		w32.DestroyWindow(hwnd)
		FreeBackBuffer(&GlobalBackBuffer)
		return 0

	case w32.WM_DESTROY:
		w32.PostQuitMessage(0)
		return 0

	case w32.WM_PAINT:
		Paint: w32.PAINTSTRUCT
		dc: w32.HDC = w32.BeginPaint(hwnd, &Paint)
		dimension: window_dimension = GetWindowDimension(hwnd)
		DisplayBufferInWindow(&GlobalBackBuffer, dc, dimension.width, dimension.height)
		w32.EndPaint(hwnd, &Paint)
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

	InitBackBuffer(&GlobalBackBuffer, 1280, 720)

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
		DeviceContext := w32.GetDC(hwnd)
		blue_offset: i32 = 0
		green_offset: i32 = 0

		for GlobalRunning {
			w32.ShowWindow(hwnd, w32.SW_SHOW)
			w32.UpdateWindow(hwnd)

			msg: w32.MSG

			for w32.PeekMessageW(&msg, nil, 0, 0, w32.PM_REMOVE) != false {
				VKCode := u32(msg.wParam)
				switch msg.message {

				case w32.WM_QUIT:
					GlobalRunning = false

				case w32.WM_KEYDOWN:
					if VKCode == 'W' {
						green_offset -= 10
					} else if VKCode == 'S' {
						green_offset += 10
					} else if VKCode == 'A' {
						blue_offset += 10
					} else if VKCode == 'D' {
						blue_offset -= 10
					}
					if VKCode == w32.VK_ESCAPE {
						w32.PostQuitMessage(0)
						GlobalRunning = false
					}
				}

				w32.TranslateMessage(&msg)
				w32.DispatchMessageW(&msg)

			}

			//			RenderWeirdGradient(blue_offset, green_offset)
			InitTileMap(TileMap, DeviceContext)
			dimension := GetWindowDimension(hwnd)
			DisplayBufferInWindow(
				&GlobalBackBuffer,
				DeviceContext,
				dimension.width,
				dimension.height,
			)
			if !GlobalRunning {
				FreeBackBuffer(&GlobalBackBuffer)
			}
		}
	}
}
