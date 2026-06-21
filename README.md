# ComputerCraft Project

A small CC:Tweaked/ComputerCraft Lua project that you can edit in VS Code, push to GitHub, and update in-game with one command.

## Project Layout

```text
.
+-- src/
|   +-- startup.lua
|   +-- main.lua
|   +-- lib/
|       +-- logger.lua
+-- update.lua
+-- README.md
+-- .gitignore
```

- `src/startup.lua` runs automatically when the ComputerCraft computer boots.
- `src/main.lua` is the main program.
- `src/lib/` is for small helper modules.
- `update.lua` runs inside CC:Tweaked and downloads the latest files from GitHub.

## First Setup

Create a new GitHub repository, then edit the variables at the top of `update.lua`:

```lua
local githubUser = "<USER>"
local githubRepo = "<REPO>"
local branch = "main"
```

This project is configured for `Wassaaa/cccreate`.

## Push Updates From VS Code

After editing files in VS Code:

```powershell
git add .
git commit -m "Update ComputerCraft project"
git branch -M main
git remote add origin git@github.com:Wassaaa/cccreate.git
git push -u origin main
```

For later updates, you usually only need:

```powershell
git add .
git commit -m "Update code"
git push
```

## Install Or Update In-Game

On the ComputerCraft computer, download the updater:

```text
wget https://raw.githubusercontent.com/Wassaaa/cccreate/main/update.lua update
```

Then run:

```text
update
reboot
```

After that, your ComputerCraft computer will have the latest files from the `src/` folder.

## Fetch The Latest Code Later

Whenever you push new changes to GitHub, update the in-game computer with:

```text
update
reboot
```

If you change `update.lua` itself, download it again with `wget` first.
