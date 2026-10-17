import customtkinter as ctk

WORK_COLOR = "#4caf50"
REST_COLOR = "#3b8ed0"
DONE_COLOR = "#f5c542"
MUTED = "#9a9a9a"


def _fmt(seconds):
    h, rem = divmod(max(seconds, 0), 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


class TimerView(ctk.CTkFrame):
    """Running-timer UI state.

    A session is ``cycles`` repetitions of:
        focus block (``cycle_seconds``) -> rest block (``rest_seconds``)
    If ``rest_seconds`` is 0 the rest phase is skipped.
    """

    def __init__(self, master, cycle_seconds, cycles, rest_seconds, on_stop=None, rest_media=None,
                 spotify=None, db_handler=None, **kwargs):
        super().__init__(master, fg_color="transparent", **kwargs)
        self.cycle_seconds = cycle_seconds
        self.cycles = cycles
        self.rest_seconds = rest_seconds
        self.on_stop = on_stop
        self.rest_media = rest_media  # started on REST, stopped on any other phase
        self.spotify = spotify  # paused on REST (if playing), resumed when REST ends
        self.db_handler = db_handler

        self.phase = "work"  # "work", "rest" or "done"
        self.cycle = 1
        self.remaining = 0
        self.is_paused = False
        self._job = None

        self._build()

    # ---------------- UI ----------------
    def _build(self):
        card = ctk.CTkFrame(self, corner_radius=15, border_width=2, border_color="gray")
        card.pack(fill="both", expand=True, padx=20, pady=20)

        self.phase_label = ctk.CTkLabel(card, text="FOCUS", font=("", 24, "bold"))
        self.phase_label.pack(pady=(30, 5))
        self.cycle_label = ctk.CTkLabel(card, text="")
        self.cycle_label.pack()
        self.time_label = ctk.CTkLabel(card, text="00:00:00", font=("", 56, "bold"))
        self.time_label.pack(pady=(20, 10))
        self.progress = ctk.CTkProgressBar(card, width=300)
        self.progress.pack(pady=10)
        self.progress.set(0)

        # Cycle indicator dots (one per cycle)
        self.dots_frame = ctk.CTkFrame(card, fg_color="transparent")
        self.dots_frame.pack(pady=(5, 0))
        self.dots = []
        for _ in range(min(self.cycles, 20)):
            dot = ctk.CTkFrame(self.dots_frame, width=12, height=12, corner_radius=6, fg_color="#3a3a3a")
            dot.pack(side="left", padx=3)
            self.dots.append(dot)

        self.session_label = ctk.CTkLabel(card, text="", text_color=MUTED)
        self.session_label.pack(pady=(10, 0))

        controls = ctk.CTkFrame(card, fg_color="transparent")
        controls.pack(pady=20)
        self.pause_button = ctk.CTkButton(controls, text="Pause", width=90, command=self.toggle_pause)
        self.pause_button.pack(side="left", padx=5)
        self.skip_button = ctk.CTkButton(controls, text="Skip", width=90, fg_color="gray",
                                         hover_color="#555555", command=self.next_phase)
        self.skip_button.pack(side="left", padx=5)
        self.stop_button = ctk.CTkButton(controls, text="Stop", width=90, fg_color="#b22222",
                                         hover_color="#8b1a1a", command=self.stop)
        self.stop_button.pack(side="left", padx=5)

    # ---------------- State machine ----------------
    def start(self):
        self.cycle = 1
        self._enter_phase("work")

    def _enter_phase(self, phase):
        self._cancel_job()
        self.phase = phase
        self.is_paused = False
        self.pause_button.configure(text="Pause", state="normal")
        self.skip_button.configure(state="normal")

        if phase == "rest" and self.spotify is not None:
            self.spotify.pause_for_rest()

        if self.rest_media is not None:
            if phase == "rest":
                self.rest_media.start()
            else:
                self.rest_media.stop()

        if phase != "rest" and self.spotify is not None:
            # No-op unless Spotify was paused by us at the start of the rest
            self.spotify.resume_after_rest()

        if phase == "work":
            self.remaining = self.cycle_seconds
            self._set_phase_style("FOCUS", WORK_COLOR)
        elif phase == "rest":
            self.remaining = self.rest_seconds
            self._set_phase_style("REST", REST_COLOR)
        else:  # done
            self.remaining = 0
            self._set_phase_style("DONE", DONE_COLOR)
            self.cycle_label.configure(text=f"Completed {self.cycles} of {self.cycles} cycles")
            self.session_label.configure(text="Session complete")
            self.pause_button.configure(state="disabled")
            self.skip_button.configure(state="disabled")
            self.stop_button.configure(text="Back")
            self.time_label.configure(text="00:00:00")
            self.progress.set(1)
            self._update_dots()
            self.bell()
            if self.db_handler is not None:
                media_dir = self.rest_media.directory if self.rest_media is not None else None
                self.db_handler.insert_timer_history(
                    work_duration=self.cycle_seconds // 60,
                    rest_duration=self.rest_seconds // 60,
                    cycles=self.cycles,
                    rest_media_directory=media_dir,
                )
            return

        self.cycle_label.configure(text=f"Cycle {self.cycle} of {self.cycles}")
        self._update_dots()
        self._tick()

    def _set_phase_style(self, text, color):
        self.phase_label.configure(text=text, text_color=color)
        self.progress.configure(progress_color=color)

    def _update_dots(self):
        for i, dot in enumerate(self.dots, start=1):
            if self.phase == "done" or i < self.cycle:
                dot.configure(fg_color=DONE_COLOR)
            elif i == self.cycle:
                dot.configure(fg_color=WORK_COLOR if self.phase == "work" else REST_COLOR)
            else:
                dot.configure(fg_color="#3a3a3a")

    def _tick(self):
        self._render_time()
        if self.remaining <= 0:
            self.bell()
            self.next_phase()
            return
        self.remaining -= 1
        self._job = self.after(1000, self._tick)

    def next_phase(self):
        if self.phase == "work":
            if self.rest_seconds > 0:
                self._enter_phase("rest")
            else:
                self._finish_cycle()
        elif self.phase == "rest":
            self._finish_cycle()

    def _finish_cycle(self):
        if self.cycle >= self.cycles:
            self._enter_phase("done")
        else:
            self.cycle += 1
            self._enter_phase("work")

    def _session_remaining(self):
        """Seconds left in the whole session, including the current phase."""
        per_cycle = self.cycle_seconds + self.rest_seconds
        future_cycles = (self.cycles - self.cycle) * per_cycle
        if self.phase == "work":
            return self.remaining + self.rest_seconds + future_cycles
        return self.remaining + future_cycles

    def _render_time(self):
        self.time_label.configure(text=_fmt(self.remaining))
        total = self.cycle_seconds if self.phase == "work" else self.rest_seconds
        self.progress.set(1 - self.remaining / total if total else 0)
        self.session_label.configure(text=f"Session remaining: {_fmt(self._session_remaining())}")

    # ---------------- Controls ----------------
    def toggle_pause(self):
        if self.is_paused:
            self.is_paused = False
            self.pause_button.configure(text="Pause")
            self._job = self.after(1000, self._tick)
        else:
            self.is_paused = True
            self.pause_button.configure(text="Resume")
            self._cancel_job()

    def stop(self):
        self._cancel_job()
        self._stop_media()
        if self.on_stop:
            self.on_stop()

    def _stop_media(self):
        if self.rest_media is not None:
            self.rest_media.stop()
        if self.spotify is not None:
            self.spotify.resume_after_rest()

    def _cancel_job(self):
        if self._job is not None:
            self.after_cancel(self._job)
            self._job = None

    def destroy(self):
        self._cancel_job()
        self._stop_media()
        super().destroy()
