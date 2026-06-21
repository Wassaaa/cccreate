import argparse
import ctypes
import time
from ctypes import wintypes


user32 = ctypes.WinDLL("user32", use_last_error=True)

EnumWindowsProc = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

WM_KEYDOWN = 0x0100
WM_KEYUP = 0x0101
WM_CHAR = 0x0102
VK_RETURN = 0x0D


user32.EnumWindows.argtypes = [EnumWindowsProc, wintypes.LPARAM]
user32.EnumWindows.restype = wintypes.BOOL
user32.GetWindowTextLengthW.argtypes = [wintypes.HWND]
user32.GetWindowTextLengthW.restype = ctypes.c_int
user32.GetWindowTextW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
user32.GetWindowTextW.restype = ctypes.c_int
user32.IsWindowVisible.argtypes = [wintypes.HWND]
user32.IsWindowVisible.restype = wintypes.BOOL
user32.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
user32.PostMessageW.restype = wintypes.BOOL


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
    title_contains = title_contains.lower()
    matches = []

    for hwnd, title in list_windows():
        if title_contains in title.lower():
            matches.append((hwnd, title))

    return matches


def post_char(hwnd, char):
    ok = user32.PostMessageW(hwnd, WM_CHAR, ord(char), 0)
    if not ok:
        raise ctypes.WinError(ctypes.get_last_error())


def post_enter(hwnd):
    if not user32.PostMessageW(hwnd, WM_KEYDOWN, VK_RETURN, 0):
        raise ctypes.WinError(ctypes.get_last_error())

    if not user32.PostMessageW(hwnd, WM_KEYUP, VK_RETURN, 0):
        raise ctypes.WinError(ctypes.get_last_error())


def send_text(hwnd, text, press_enter=True, delay=0.01):
    for char in text:
        if char == "\n":
            post_enter(hwnd)
        else:
            post_char(hwnd, char)
        time.sleep(delay)

    if press_enter:
        post_enter(hwnd)


def choose_window(matches):
    if not matches:
        raise SystemExit("No matching window found.")

    if len(matches) > 1:
        print("Multiple matching windows found:")
        for index, (hwnd, title) in enumerate(matches, start=1):
            print(f"{index}. hwnd={hwnd} title={title}")
        raise SystemExit("Use a more specific --title value.")

    return matches[0]


def main():
    parser = argparse.ArgumentParser(description="Send text to a Minecraft/ComputerCraft window.")
    parser.add_argument("text", nargs="?", help="Text to send, for example: update")
    parser.add_argument("--title", default="Minecraft", help="Window title substring to target.")
    parser.add_argument("--list", action="store_true", help="List visible windows and exit.")
    parser.add_argument("--no-enter", action="store_true", help="Do not press Enter after text.")
    parser.add_argument("--delay", type=float, default=0.01, help="Delay between characters.")
    args = parser.parse_args()

    if args.list:
        for hwnd, title in list_windows():
            print(f"hwnd={hwnd} title={title}")
        return

    if not args.text:
        raise SystemExit("Provide text to send, or use --list.")

    hwnd, title = choose_window(find_window(args.title))
    print(f"Target: hwnd={hwnd} title={title}")

    send_text(hwnd, args.text, press_enter=not args.no_enter, delay=args.delay)
    print("Sent.")


if __name__ == "__main__":
    main()
