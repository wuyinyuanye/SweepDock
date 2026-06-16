#!/usr/bin/env python3
import queue
import os
import shutil
import subprocess
import threading
import tkinter as tk
from tkinter import messagebox


PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"


class SweepDock(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("SweepDock")
        self.geometry("980x680")
        self.minsize(900, 620)

        self.output_queue = queue.Queue()
        self.mo_path = None
        self.is_running = False

        self.configure(bg="#f5f5f7")
        self._build_ui()
        self.refresh_mole()
        self.after(100, self._drain_output)

    def _build_ui(self):
        sidebar = tk.Frame(self, width=310, bg="#f5f5f7", padx=20, pady=20)
        sidebar.pack(side="left", fill="y")
        sidebar.pack_propagate(False)

        title = tk.Label(sidebar, text="SweepDock", bg="#f5f5f7", fg="#1d1d1f", font=("Helvetica Neue", 30, "bold"))
        title.pack(anchor="w")

        subtitle = tk.Label(
            sidebar,
            text="Native desktop wrapper for Mole CLI",
            bg="#f5f5f7",
            fg="#6e6e73",
            font=("Helvetica Neue", 12),
        )
        subtitle.pack(anchor="w", pady=(4, 18))

        self.status_var = tk.StringVar()
        self.path_var = tk.StringVar()

        status_card = tk.Frame(sidebar, bg="#e9e9ee", padx=14, pady=12)
        status_card.pack(fill="x", pady=(0, 18))

        self.status_label = tk.Label(
            status_card,
            textvariable=self.status_var,
            bg="#e9e9ee",
            fg="#1d1d1f",
            font=("Helvetica Neue", 14, "bold"),
        )
        self.status_label.pack(anchor="w")

        path_label = tk.Label(
            status_card,
            textvariable=self.path_var,
            bg="#e9e9ee",
            fg="#6e6e73",
            justify="left",
            wraplength=250,
            font=("Helvetica Neue", 11),
        )
        path_label.pack(anchor="w", pady=(6, 0))

        actions = [
            ("System Status", "Show machine and storage overview", ["status"], False),
            ("Disk Analyze", "Find large folders and files", ["analyze"], False),
            ("Cleanup Preview", "Dry-run only, no deletion", ["clean", "--dry-run"], False),
            ("Run Cleanup", "Requires confirmation", ["clean"], True),
            ("Mole Help", "Show available CLI commands", ["--help"], False),
        ]

        for name, desc, args, destructive in actions:
            button = tk.Button(
                sidebar,
                text=f"{name}\n{desc}",
                anchor="w",
                justify="left",
                padx=12,
                pady=8,
                relief="flat",
                bg="#ffffff",
                activebackground="#e5f0ff",
                fg="#1d1d1f",
                font=("Helvetica Neue", 12),
                command=lambda a=args, d=destructive: self.run_action(a, d),
            )
            button.pack(fill="x", pady=5)

        spacer = tk.Frame(sidebar, bg="#f5f5f7")
        spacer.pack(fill="both", expand=True)

        refresh = tk.Button(
            sidebar,
            text="Refresh",
            padx=12,
            pady=8,
            relief="flat",
            bg="#1d1d1f",
            activebackground="#3a3a3c",
            fg="#ffffff",
            activeforeground="#ffffff",
            font=("Helvetica Neue", 12, "bold"),
            command=self.refresh_mole,
        )
        refresh.pack(fill="x")

        main = tk.Frame(self, bg="#ffffff", padx=0, pady=0)
        main.pack(side="left", fill="both", expand=True)

        header = tk.Frame(main, bg="#ffffff", padx=22, pady=18)
        header.pack(fill="x")

        self.command_var = tk.StringVar(value="No command has run yet.")
        tk.Label(
            header,
            text="Command Output",
            bg="#ffffff",
            fg="#1d1d1f",
            font=("Helvetica Neue", 20, "bold"),
        ).pack(anchor="w")
        tk.Label(
            header,
            textvariable=self.command_var,
            bg="#ffffff",
            fg="#6e6e73",
            font=("Helvetica Neue", 11),
        ).pack(anchor="w", pady=(3, 0))

        output_frame = tk.Frame(main, bg="#ffffff", padx=22, pady=(0, 18))
        output_frame.pack(fill="both", expand=True)

        self.output = tk.Text(
            output_frame,
            wrap="word",
            bg="#ffffff",
            fg="#1d1d1f",
            insertbackground="#1d1d1f",
            relief="flat",
            padx=16,
            pady=16,
            font=("SF Mono", 12),
        )
        self.output.pack(side="left", fill="both", expand=True)

        scrollbar = tk.Scrollbar(output_frame, orient="vertical", command=self.output.yview)
        scrollbar.pack(side="right", fill="y")
        self.output.configure(yscrollcommand=scrollbar.set)

        self._set_output("Welcome to SweepDock.\n\nClick a command on the left. Cleanup Preview is always the recommended first step.")

    def refresh_mole(self):
        self.mo_path = self._find_mo()
        if self.mo_path:
            self.status_var.set("Mole CLI ready")
            self.path_var.set(self.mo_path)
        else:
            self.status_var.set("Mole CLI missing")
            self.path_var.set("Install with: brew install mole")
            self._set_output(
                "Mole CLI was not detected.\n\n"
                "Install it with Homebrew:\n"
                "  brew install mole\n\n"
                "SweepDock calls the official CLI instead of reimplementing cleanup logic."
            )

    def run_action(self, args, destructive):
        if self.is_running:
            return

        if destructive:
            confirmed = messagebox.askyesno(
                "Run real cleanup?",
                "Preview first with Cleanup Preview.\n\n"
                "Real cleanup may permanently delete caches, logs, and generated files.\n\n"
                "Do you want to run mo clean now?",
                icon="warning",
            )
            if not confirmed:
                return

        if not self.mo_path:
            self.refresh_mole()
            return

        self.is_running = True
        command = [self.mo_path] + args
        self.command_var.set("Running: " + " ".join(command))
        self._set_output("$ " + " ".join(command) + "\n\nRunning...")

        thread = threading.Thread(target=self._run_command, args=(command,), daemon=True)
        thread.start()

    def _run_command(self, command):
        try:
            completed = subprocess.run(
                command,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                env={"PATH": PATH, "TERM": "xterm-256color", "LC_ALL": "en_US.UTF-8"},
            )
            output = completed.stdout or "(No output)"
            self.output_queue.put(("done", command, completed.returncode, output))
        except Exception as exc:
            self.output_queue.put(("done", command, 126, f"Failed to run command: {exc}"))

    def _drain_output(self):
        try:
            while True:
                kind, command, code, output = self.output_queue.get_nowait()
                if kind == "done":
                    self.is_running = False
                    self.command_var.set(f"{' '.join(command)} exited with code {code}")
                    self._set_output("$ " + " ".join(command) + "\n\n" + output)
        except queue.Empty:
            pass

        self.after(100, self._drain_output)

    def _set_output(self, text):
        self.output.configure(state="normal")
        self.output.delete("1.0", "end")
        self.output.insert("1.0", text)
        self.output.configure(state="disabled")

    def _find_mo(self):
        for path in [
            "/opt/homebrew/bin/mo",
            "/usr/local/bin/mo",
            "/usr/bin/mo",
            "/bin/mo",
        ]:
            if os.path.isfile(path) and os.access(path, os.X_OK):
                return path
        return shutil.which("mo", path=PATH)


if __name__ == "__main__":
    SweepDock().mainloop()
