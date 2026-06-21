import argparse
import ctypes
import struct
from ctypes import wintypes
from pathlib import Path


user32 = ctypes.WinDLL("user32", use_last_error=True)
gdi32 = ctypes.WinDLL("gdi32", use_last_error=True)

EnumWindowsProc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

SRCCOPY = 0x00CC0020
PW_RENDERFULLCONTENT = 0x00000002
BI_RGB = 0
DIB_RGB_COLORS = 0


class RECT(ctypes.Structure):
    _fields_ = [
        ("left", wintypes.LONG),
        ("top", wintypes.LONG),
        ("right", wintypes.LONG),
        ("bottom", wintypes.LONG),
    ]


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", wintypes.DWORD),
        ("biWidth", wintypes.LONG),
        ("biHeight", wintypes.LONG),
        ("biPlanes", wintypes.WORD),
        ("biBitCount", wintypes.WORD),
        ("biCompression", wintypes.DWORD),
        ("biSizeImage", wintypes.DWORD),
        ("biXPelsPerMeter", wintypes.LONG),
        ("biYPelsPerMeter", wintypes.LONG),
        ("biClrUsed", wintypes.DWORD),
        ("biClrImportant", wintypes.DWORD),
    ]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [("bmiHeader", BITMAPINFOHEADER), ("bmiColors", wintypes.DWORD * 3)]


user32.EnumWindows.argtypes = [EnumWindowsProc, wintypes.LPARAM]
user32.EnumWindows.restype = wintypes.BOOL
user32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
user32.GetWindowTextLengthW.restype = ctypes.c_int
user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
user32.GetWindowTextW.restype = ctypes.c_int
user32.IsWindowVisible.argtypes = [wintypes.HWND]
user32.IsWindowVisible.restype = wintypes.BOOL
user32.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(RECT)]
user32.GetWindowRect.restype = wintypes.BOOL
user32.GetWindowDC.argtypes = [wintypes.HWND]
user32.GetWindowDC.restype = wintypes.HDC
user32.GetDC.argtypes = [wintypes.HWND]
user32.GetDC.restype = wintypes.HDC
user32.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]
user32.ReleaseDC.restype = ctypes.c_int
user32.PrintWindow.argtypes = [wintypes.HWND, wintypes.HDC, wintypes.UINT]
user32.PrintWindow.restype = wintypes.BOOL

gdi32.CreateCompatibleDC.argtypes = [wintypes.HDC]
gdi32.CreateCompatibleDC.restype = wintypes.HDC
gdi32.CreateCompatibleBitmap.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int]
gdi32.CreateCompatibleBitmap.restype = wintypes.HBITMAP
gdi32.SelectObject.argtypes = [wintypes.HDC, wintypes.HGDIOBJ]
gdi32.SelectObject.restype = wintypes.HGDIOBJ
gdi32.BitBlt.argtypes = [
    wintypes.HDC,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    wintypes.HDC,
    ctypes.c_int,
    ctypes.c_int,
    wintypes.DWORD,
]
gdi32.BitBlt.restype = wintypes.BOOL
gdi32.GetDIBits.argtypes = [
    wintypes.HDC,
    wintypes.HBITMAP,
    wintypes.UINT,
    wintypes.UINT,
    wintypes.LPVOID,
    ctypes.POINTER(BITMAPINFO),
    wintypes.UINT,
]
gdi32.GetDIBits.restype = ctypes.c_int
gdi32.DeleteObject.argtypes = [wintypes.HGDIOBJ]
gdi32.DeleteObject.restype = wintypes.BOOL
gdi32.DeleteDC.argtypes = [wintypes.HDC]
gdi32.DeleteDC.restype = wintypes.BOOL


def get_window_title(hwnd):
    length = user32.GetWindowTextLengthW(hwnd)
    if length == 0:
        return ""

    buffer = ctypes.create_unicode_buffer(length + 1)
    user32.GetWindowTextW(hwnd, buffer, length + 1)
    return buffer.value


def list_windows():
    windows = []

    @EnumWindowsProc
    def callback(hwnd, _):
        if user32.IsWindowVisible(hwnd):
            title = get_window_title(hwnd)
            if title:
                windows.append((hwnd, title))
        return True

    user32.EnumWindows(callback, 0)
    return windows


def find_window(title_contains):
    needle = title_contains.lower()
    return [(hwnd, title) for hwnd, title in list_windows() if needle in title.lower()]


def choose_window(matches):
    if not matches:
        raise SystemExit("No matching window found.")

    if len(matches) > 1:
        for index, (hwnd, title) in enumerate(matches, start=1):
            print(f"{index}. hwnd={hwnd} title={title}")
        raise SystemExit("Use a more specific --title value.")

    return matches[0]


def window_rect(hwnd):
    rect = RECT()
    if not user32.GetWindowRect(hwnd, ctypes.byref(rect)):
        raise ctypes.WinError(ctypes.get_last_error())

    width = rect.right - rect.left
    height = rect.bottom - rect.top
    if width <= 0 or height <= 0:
        raise SystemExit("Window has invalid size.")

    return rect, width, height


def save_bmp(path, width, height, pixels):
    row_size = width * 4
    image_size = row_size * height
    file_size = 14 + 40 + image_size

    with open(path, "wb") as handle:
        handle.write(b"BM")
        handle.write(struct.pack("<IHHI", file_size, 0, 0, 14 + 40))
        handle.write(
            struct.pack(
                "<IiiHHIIiiII",
                40,
                width,
                height,
                1,
                32,
                BI_RGB,
                image_size,
                0,
                0,
                0,
                0,
            )
        )
        handle.write(pixels)


def capture(hwnd, output_path, method):
    rect, width, height = window_rect(hwnd)

    if method == "screen":
        source_dc = user32.GetDC(None)
        source_x = rect.left
        source_y = rect.top
    else:
        source_dc = user32.GetWindowDC(hwnd)
        source_x = 0
        source_y = 0

    if not source_dc:
        raise ctypes.WinError(ctypes.get_last_error())

    memory_dc = gdi32.CreateCompatibleDC(source_dc)
    bitmap = gdi32.CreateCompatibleBitmap(source_dc, width, height)
    old_object = gdi32.SelectObject(memory_dc, bitmap)

    try:
        if method == "printwindow":
            ok = user32.PrintWindow(hwnd, memory_dc, PW_RENDERFULLCONTENT)
            if not ok:
                raise ctypes.WinError(ctypes.get_last_error())
        else:
            ok = gdi32.BitBlt(memory_dc, 0, 0, width, height, source_dc, source_x, source_y, SRCCOPY)
            if not ok:
                raise ctypes.WinError(ctypes.get_last_error())

        info = BITMAPINFO()
        info.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
        info.bmiHeader.biWidth = width
        info.bmiHeader.biHeight = height
        info.bmiHeader.biPlanes = 1
        info.bmiHeader.biBitCount = 32
        info.bmiHeader.biCompression = BI_RGB

        buffer_size = width * height * 4
        buffer = ctypes.create_string_buffer(buffer_size)

        lines = gdi32.GetDIBits(memory_dc, bitmap, 0, height, buffer, ctypes.byref(info), DIB_RGB_COLORS)
        if lines == 0:
            raise ctypes.WinError(ctypes.get_last_error())

        save_bmp(output_path, width, height, buffer.raw)
    finally:
        gdi32.SelectObject(memory_dc, old_object)
        gdi32.DeleteObject(bitmap)
        gdi32.DeleteDC(memory_dc)
        if method == "screen":
            user32.ReleaseDC(None, source_dc)
        else:
            user32.ReleaseDC(hwnd, source_dc)


def main():
    parser = argparse.ArgumentParser(description="Capture a Minecraft window screenshot as BMP.")
    parser.add_argument("--title", default="Minecraft", help="Window title substring to target.")
    parser.add_argument("--list", action="store_true", help="List visible windows and exit.")
    parser.add_argument("--method", choices=["printwindow", "screen"], default="printwindow")
    parser.add_argument("--out", default="inbox/minecraft-window.bmp", help="Output BMP path.")
    args = parser.parse_args()

    if args.list:
        for hwnd, title in list_windows():
            print(f"hwnd={hwnd} title={title}")
        return

    hwnd, title = choose_window(find_window(args.title))
    output_path = Path(args.out).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    capture(hwnd, output_path, args.method)
    print(f"Captured {title} to {output_path}")


if __name__ == "__main__":
    main()
