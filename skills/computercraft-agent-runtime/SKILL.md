---
name: computercraft-agent-runtime
description: "Operate and debug a ComputerCraft/CC:Tweaked project through agent-side tooling. Use when working with webhook reports, report_shell aliases, background Minecraft key or mouse sending, Minecraft screenshots or cropped OCR-style inspection, local webhook receiver/proxy/DDNS health, in-game update/deploy loops, or human-in-the-loop Minecraft setup for ComputerCraft testing."
---

# ComputerCraft Agent Runtime

Use this skill when the task is about controlling, observing, or debugging a live ComputerCraft/CC:Tweaked computer from the local workstation.

## Workflow

1. Read repo context:
   - `README.md` for install/update basics.
   - `docs/INGAME_DEBUGGING.md` for in-game report commands.
   - `docs/AGENT_RUNTIME.md` if present for project-specific runtime details.
2. Prefer structured reports over screenshots:
   - Read latest local report with `.\tools\read_latest_report.ps1`.
   - Ask/run `report`, `report run <program>`, or add program reports through `src/lib/reporter.lua`.
3. Use report-only shell aliases only for temporary read-only inspection:
   - `report_shell enable`
   - run `ls`, `list`, `dir`, or `id`
   - `report_shell disable`
4. Use screenshots for UI/focus/terminal-state questions:
   - Prefer cropped screenshots of the terminal or target GUI.
   - Use full-window screenshots only when world context matters.
5. Use background key/mouse sending only after visual state is known.
6. Ask the player for physical setup changes when block placement, orientation, modem attachment, GUI configuration, or crosshair alignment matters.

## References

- Agent runtime commands, screenshot/keysend usage, webhook stack checks, report-shell rules, and human-in-the-loop boundary: `references/agent-runtime.md`.
