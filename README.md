# The AI Workspace

A multi-agent development workspace built on **OpenCode**, **Backlog.md**, and
**Zellij** — packaged as one-shot installers for Windows (PowerShell) and
macOS/Linux (bash).

## What a package installs

| Component | Role |
|---|---|
| OpenCode + OCX (`ws` profile) | agent runtime: Plan-WS, Build-WS, Merger-WS, and friends |
| Backlog.md | task board: To Do -> In Progress -> To Review -> To Merge -> Done |
| Zellij | terminal workspace: Plan/Build/Board/Merge/Shell tabs per repo |

`setup-repo` also drops 11 board-workflow scripts into each repo (`scripts/`),
plus `SOFTWARE_ENGINEERING_PRINCIPLES.md` and task templates. Agents and the
board drive the full cycle: `start-task` -> `create-worktree` -> code ->
`complete-task` -> review (`write-verdict` / `read-verdict`) -> `approve-task`
-> `merge-task` -> `done-task`. See `profile/tools/board-workflow.md` for the
complete flow.

## Recipient quick start

1. Extract the zip
2. **Windows:** `.\bootstrap.ps1` — **macOS/Linux:** `bash bootstrap.sh`
3. Answer the prompts (project name, repos, plan folder), then launch Zellij:

   ```
   zellij --config ~/.config/zellij/config-<layout>.kdl --layout <layout>
   ```

   (Windows path: `$env:APPDATA\Zellij\config\config-<layout>.kdl`)

4. Press `a` in a tab (via `Ctrl+t` first) to duplicate it into a fresh agent tab
5. Full walkthrough: `QUICKSTART.txt` — to undo everything: `uninstall.ps1` / `uninstall.sh`

## Repository layout (this repo)

| Path | Ships in |
|---|---|
| `*.ps1`, `config-ws.kdl`, `profile/` | **windows** zip (PowerShell tree) |
| `unix/*.sh`, `unix/config-ws.kdl`, `unix/profile/` | **macos** + **linux** zips (bash tree) |

Both trees are behaviorally identical — same 11 workflow scripts, same guards,
exit codes, and output tags, same Zellij layouts and keybinds. The bash tree
runs on macOS's stock bash 3.2 and supports apt/dnf/pacman (brew on macOS;
Zellij installs as a prebuilt binary to `~/.local/bin` on Linux).

## Packaging (from any OS)

```
pwsh:  & package.ps1 -OS windows | macos | linux
bash:  bash package.sh [windows | macos | linux | all]
```

Output: `TheAIWorkSpace-<date>-<os>.zip`. Both packagers produce identical
zips, and all text in macos/linux zips is LF-normalized. `package.sh` needs
`zip` installed (`--dry-run` works without it).

Version pins (OpenCode V1 line): `ocx@2.0.15` (frozen V1 client),
`opencode-ai@1`, `backlog.md@1`.

## Releases

Releases are built by CI, not uploaded by hand. Pushing a tag (`v*`) triggers
[`.github/workflows/release.yml`](.github/workflows/release.yml), which builds
all 3 zips on an `ubuntu-latest` runner via `bash package.sh` and publishes
them to a GitHub Release with generated notes:

```
git tag v1.0.0
git push origin v1.0.0
```

Manual dispatch (Actions tab -> Release -> Run workflow) builds all 3 zips
for validation, without publishing a release.

## Maintenance

- After editing `profile/`, regenerate the bash copy and repackage:

  ```
  bash unix/sync-profile.sh
  git diff unix/profile
  ```
