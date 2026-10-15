import os
import sys
import platform
import tkinter as tk
import customtkinter as ctk
from tkinter import filedialog
from utils.paths import get_resource_path, restore_child_environment
from media_controls.spotify_handler import Spotify_Handler
from media_controls.rest_media_handler import RestMediaHandler
from ui.timer_view import TimerView
from threading import Thread
ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

ACCENT = "#4caf50"
MUTED = "#9a9a9a"

# ---------------- OS checker ----------------
OS_NAME = platform.system()  # "Linux", "Windows", "Darwin", ...
IS_LINUX = OS_NAME == "Linux"
IS_WINDOWS = OS_NAME == "Windows"

# Assets live in <project root>/assets from source, or inside the PyInstaller bundle when frozen
LOGO_PATH = get_resource_path("assets/timer-logo.png")
ICO_PATH = get_resource_path("assets/timer-logo.ico")

# Frozen builds: make sure spawned tools (playerctl, mpv, vlc, ...) use the host's libraries
restore_child_environment()


class Main:
    def __init__(self):
        self.cycle_duration = None
        self.num_cycles = None
        self.rest_interval = None
        self.timer_view = None
        self.should_continue = True
        self.spotify_handler = Spotify_Handler(continue_checker=self.should_continue)
        self.rest_media = RestMediaHandler()

    def start(self):
        try:
            self.root = ctk.CTk()
            self.root.title("Pomodoro Timer")
            self.root.geometry("460x620")
            # Make sure rest media never outlives the app
            self.root.protocol("WM_DELETE_WINDOW", self._on_close)
            #TITLE BAR
            # Window/taskbar icon (also used on Linux while minimized / in the dock)
            self._set_native_icon()
            if IS_LINUX:
                # Linux: hide the native title bar and draw our own (with the logo)
                self.root.overrideredirect(True)
                self._title_bar()

            # Home view (input + history). Swapped out for the timer view when running.
            self.home_frame = ctk.CTkFrame(self.root, fg_color="transparent")
            self.home_frame.pack(fill="both", expand=True)
            #Header Part
            header = ctk.CTkLabel(self.home_frame, text="Welcome to Pomodoro Timer", font=("", 20, "bold"))
            header.pack(fill="x", padx=10, pady=(15, 2))
            sub_header = ctk.CTkLabel(self.home_frame, text="Start Timer or choose from existing history",
                                      text_color=MUTED)
            sub_header.pack(fill="x", padx=10, pady=(0, 5))
            #Start timer or choose timer history section
            # self._start_spotify_handler()
            self._timer_input_section()
            self._history_section()
            while self.root.mainloop():
                self.should_continue = True
            self.should_continue = False
        except Exception as e:
            self.should_continue = False

    def _select_media(self):
        directory = filedialog.askdirectory(title="Select folder")
        if not directory:
            return
        count = self.rest_media.set_directory(directory)
        folder = os.path.basename(directory) or directory
        if count == 0:
            self.media_label.configure(text=f"No audio/video files in '{folder}'", text_color="#ff5555")
        elif self.rest_media.player_name is None:
            self.media_label.configure(text="No media player found - install mpv, ffmpeg or VLC",
                                       text_color="#ff5555")
        else:
            mode = "will loop" if count == 1 else "shuffled"
            self.media_label.configure(text=f"Rest media: '{folder}' - {count} file(s), {mode}",
                                       text_color=MUTED)

    def _on_close(self):
        self.rest_media.stop()
        self.root.destroy()  # destroys TimerView, which queues a Spotify resume if needed
        # Let the queued resume finish before the process exits
        self.spotify_handler.wait_until_idle(timeout=5)

    def _start_spotify_handler(self):
        thread = Thread(
            target=self.spotify_handler.start_handler,
            daemon=True
        )
        thread.start()

    def _timer_input_section(self):
        card = ctk.CTkFrame(self.home_frame, corner_radius=15, border_width=2, border_color="gray")
        card.pack(fill="x", padx=15, pady=10)
        inner = ctk.CTkFrame(card, fg_color="transparent")
        inner.pack(fill="both", expand=True, padx=15, pady=15)
        inner.grid_columnconfigure(0, weight=1)

        title = ctk.CTkLabel(inner, text="New Timer", font=("", 16, "bold"), anchor="w")
        title.grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 10))

        # Only allow up to 3 digits in every field
        vcmd = (self.root.register(lambda p: p == "" or (p.isdigit() and len(p) <= 3)), "%P")

        self.cycle_duration = self._input_row(inner, 1, "Cycle duration", "Focus time per cycle", "min", "25", vcmd)
        self.num_cycles = self._input_row(inner, 2, "Number of cycles", "Focus + rest repeats", "x", "4", vcmd)
        self.rest_interval = self._input_row(inner, 3, "Rest interval", "Break after each cycle", "min", "5", vcmd)

        # Live summary of total session length
        self.summary_label = ctk.CTkLabel(inner, text="", text_color=MUTED, anchor="w")
        self.summary_label.grid(row=4, column=0, columnspan=3, sticky="w", pady=(10, 0))
        for entry in (self.cycle_duration, self.num_cycles, self.rest_interval):
            entry.bind("<KeyRelease>", self._update_summary)
        self._update_summary()

        self.error_label = ctk.CTkLabel(inner, text="", text_color="#ff5555", anchor="w")
        self.error_label.grid(row=5, column=0, columnspan=3, sticky="w")

        buttons = ctk.CTkFrame(inner, fg_color="transparent")
        buttons.grid(row=6, column=0, columnspan=3, sticky="ew", pady=(5, 0))
        buttons.grid_columnconfigure((0, 1), weight=1)
        start_button = ctk.CTkButton(
            buttons,
            text="Start Timer",
            corner_radius=10,
            height=36,
            fg_color=ACCENT,
            hover_color="#3d8b40",
            font=("", 14, "bold"),
            command=self._start_timer
        )
        start_button.grid(row=0, column=0, sticky="ew", padx=(0, 5))
        select_media_button = ctk.CTkButton(
            buttons,
            text="Select Rest Media",
            corner_radius=10,
            height=36,
            fg_color="#2b2b2b",
            hover_color="gray",
            border_width=1,
            border_color="gray",
            command=self._select_media
        )
        select_media_button.grid(row=0, column=1, sticky="ew", padx=(5, 0))

        self.media_label = ctk.CTkLabel(inner, text="No rest media selected", text_color=MUTED,
                                        font=("", 11), anchor="w")
        self.media_label.grid(row=7, column=0, columnspan=3, sticky="w", pady=(5, 0))

    def _input_row(self, parent, row, title, hint, unit, default, vcmd):
        labels = ctk.CTkFrame(parent, fg_color="transparent")
        labels.grid(row=row, column=0, sticky="w", pady=6)
        ctk.CTkLabel(labels, text=title, font=("", 13, "bold"), anchor="w", height=18).pack(anchor="w")
        ctk.CTkLabel(labels, text=hint, text_color=MUTED, font=("", 11), anchor="w", height=14).pack(anchor="w")
        entry = ctk.CTkEntry(parent, width=70, justify="center", validate="key", validatecommand=vcmd)
        entry.insert(0, default)
        entry.grid(row=row, column=1, padx=(10, 5), pady=6)
        ctk.CTkLabel(parent, text=unit, text_color=MUTED, width=30, anchor="w").grid(row=row, column=2, sticky="w")
        return entry

    def _history_section(self):
        history_section = ctk.CTkFrame(self.home_frame, corner_radius=15, border_color="gray", border_width=2,
                                       fg_color="transparent")
        history_section.pack(fill="both", expand=True, padx=15, pady=(0, 15))
        inner = ctk.CTkFrame(history_section, fg_color="transparent")
        inner.pack(fill="both", expand=True, padx=15, pady=15)
        timer_history_label = ctk.CTkLabel(inner, text="Timer History", font=("", 16, "bold"), anchor="w")
        timer_history_label.pack(anchor="w")

    def _title_bar(self):
        """Custom title bar - only used on Linux, where the native one is disabled."""
        bar = ctk.CTkFrame(self.root, corner_radius=0, height=32)
        bar.pack(fill="x")
        bar.pack_propagate(False)

        self._title_logo = self._load_logo(18)
        if self._title_logo is not None:
            logo = ctk.CTkLabel(bar, text="", image=self._title_logo, width=18)
            logo.pack(side="left", padx=(10, 0))
            self._make_draggable(logo)

        title = ctk.CTkLabel(bar, text="Pomodoro Timer", anchor="w")
        title.pack(side="left", padx=(6 if self._title_logo is not None else 10, 0))

        close = ctk.CTkButton(bar, text="X", width=32, height=22, corner_radius=4,
                              fg_color="transparent", hover_color="#e81123",
                              text_color="white", command=self._on_close)
        close.pack(side="right", padx=(0, 6))

        minimize = ctk.CTkButton(bar, text="-", width=32, height=22, corner_radius=4,
                                 fg_color="transparent", hover_color="#3c3c3c",
                                 text_color="white", command=self._minimize)
        minimize.pack(side="right", padx=(0, 2))

        # Without a native title bar the window must be moved via our own bar
        self._make_draggable(bar)
        self._make_draggable(title)
        # Borderless windows don't get keyboard focus automatically on X11
        self.root.bind("<Button-1>", lambda e: self.root.focus_force(), add="+")
        # Re-apply borderless mode when restored from the taskbar after minimizing
        self.root.bind("<Map>", self._on_restore, add="+")

    def _make_draggable(self, widget):
        widget.bind("<ButtonPress-1>", self._start_drag, add="+")
        widget.bind("<B1-Motion>", self._on_drag, add="+")

    def _start_drag(self, event):
        self._drag_x = event.x_root - self.root.winfo_x()
        self._drag_y = event.y_root - self.root.winfo_y()

    def _on_drag(self, event):
        self.root.geometry(f"+{event.x_root - self._drag_x}+{event.y_root - self._drag_y}")

    def _minimize(self):
        # iconify() is ignored for overrideredirect windows, so temporarily
        # hand the window back to the window manager to minimize it.
        self.root.overrideredirect(False)
        self.root.iconify()

    def _on_restore(self, event=None):
        if IS_LINUX and event is not None and event.widget is self.root \
                and not self.root.overrideredirect():
            self.root.after(10, lambda: self.root.overrideredirect(True))

    def _set_native_icon(self):
        """Show the timer logo as the window/taskbar icon (.ico on Windows, .png elsewhere)."""
        if IS_WINDOWS:
            # Give the app its own taskbar identity so Windows shows our icon, not python.exe's
            try:
                import ctypes
                ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID("pomodoro.timer")
            except Exception:
                pass
            if os.path.exists(ICO_PATH):
                try:
                    # Multi-resolution .ico looks crisp in title bar, taskbar and Alt+Tab.
                    # Calling iconbitmap also stops CustomTkinter from swapping in its own icon.
                    self.root.iconbitmap(default=ICO_PATH)
                    return
                except Exception:
                    pass
        if not os.path.exists(LOGO_PATH):
            return
        try:
            self._icon_image = tk.PhotoImage(file=LOGO_PATH)
            self.root.iconphoto(True, self._icon_image)
        except Exception:
            return
        # CustomTkinter swaps in its own default icon ~200ms after startup on Windows,
        # so re-apply ours after that.
        self.root.after(300, lambda: self.root.iconphoto(True, self._icon_image))

    def _load_logo(self, size):
        if not os.path.exists(LOGO_PATH):
            return None
        try:
            from PIL import Image
            img = Image.open(LOGO_PATH)
            return ctk.CTkImage(light_image=img, dark_image=img, size=(size, size))
        except ImportError:
            # Pillow not installed - fall back to plain Tk image, scaled down by integer factor
            img = tk.PhotoImage(file=LOGO_PATH)
            factor = max(1, img.width() // size)
            return img.subsample(factor, factor)

    # ---------------- Timer state ----------------
    def _read_int(self, entry) -> int:
        text = entry.get().strip()
        return int(text) if text.isdigit() else 0

    def _update_summary(self, event=None):
        duration = self._read_int(self.cycle_duration)
        cycles = self._read_int(self.num_cycles)
        rest = self._read_int(self.rest_interval)
        total = (duration + rest) * cycles
        h, m = divmod(total, 60)
        self.summary_label.configure(
            text=f"{cycles} x ({duration} min focus + {rest} min rest)  =  {h}h {m:02d}m total"
        )

    def _start_timer(self):
        duration = self._read_int(self.cycle_duration)
        cycles = self._read_int(self.num_cycles)
        rest = self._read_int(self.rest_interval)
        if duration <= 0:
            self.error_label.configure(text="Cycle duration must be at least 1 minute")
            return
        if cycles <= 0:
            self.error_label.configure(text="Number of cycles must be at least 1")
            return
        self.error_label.configure(text="")
        # Each timer session gets a fresh "already played" memory
        self.rest_media.reset_session()
        # Show the timer UI state only when a timer is started
        self.home_frame.pack_forget()
        self.timer_view = TimerView(
            self.root,
            cycle_seconds=duration * 60,
            cycles=cycles,
            rest_seconds=rest * 60,
            on_stop=self._stop_timer,
            rest_media=self.rest_media,
            spotify=self.spotify_handler,
        )
        self.timer_view.pack(fill="both", expand=True)
        self.timer_view.start()

    def _stop_timer(self):
        if self.timer_view is not None:
            self.timer_view.destroy()
            self.timer_view = None
        self.home_frame.pack(fill="both", expand=True)


if __name__ == "__main__":
    main = Main()
    main.start()