# AGENTS.md

Guidance for anyone changing this repository, whether a person or an AI coding agent. OhMyDebn turns a Debian-based distro into a Cinnamon desktop for power users. How to propose a change (discuss first, then a PR to the `dev` branch) is in [CONTRIBUTING.md](CONTRIBUTING.md).

This file is for developing OhMyDebn. The skill in `config/ohmydebn-skill/` is different: it ships to users so the AI tools on their desktop understand an installed OhMyDebn.

## Repository layout

- `bin/` - every command, named `ohmydebn-*`. Installed to `/usr/share/ohmydebn/bin`, and scripts call each other by that absolute path.
- `install.sh` - the bootstrap: checks the distro, sets up apt sources and the OhMyDebn repo, installs the `ohmydebn` package, then runs `ohmydebn.sh`.
- `ohmydebn.sh` - sources `install/{packaging,config,cleanup,finalization}/all.sh`. A new file under `install/` must be sourced from its directory's `all.sh`.
- `config/` - default configs, `*.tpl` templates rendered per theme, `tile-rules.json`, and the user-facing agent skill.
- `themes/` - built-in themes, shipped as the separate `ohmydebn-themes` package.
- `tests/` - the test suite (see below).
- `VERSION` - the `ohmydebn` package version.

Two sibling repositories go with this one:

- `ohmydebn-package-build` - builds every OhMyDebn deb (including `ohmydebn` itself from this repo) and publishes the apt repos. Third-party apps packaged for OhMyDebn (Codex, Pi, Grok Build, T3 Code...) get their build scripts there.
- `ohmydebn-docs` - the user documentation site and release notes.

## The install runs again on every update

`ohmydebn-update` updates the `ohmydebn` package and reruns `install.sh`, so everything under `install/` runs on new installs and on every update of existing ones. Keep it idempotent. A change that must happen only once is guarded by a marker file in `~/.local/state/ohmydebn-config/<name>`. Marker names must be unique (the consistency tests check this). Never overwrite a file the user may have edited without such a guard and a reason.

## Testing

Run the whole suite with `tests/run.sh` (`--skip-apt-checks` skips the read-only apt queries). Everything must pass before a change is done.

- `tests/lint.sh` - `bash -n` and `shellcheck -S warning` on every shell script, `py_compile` on the Python ones.
- `tests/consistency.sh` - about 40 cross-file checks: menu case arms match their items, the menu search index matches the menu tree, no duplicate packages or keybindings, every third-party apt repo is pinned, every `-install` script runs `apt update` first, every AI installer asks the default question with its own name, tile rules match launcher titles, and more. Read the failing check's comment; it explains the bug it guards against.
- `tests/unit/test-*.sh` - mocked unit tests built on `tests/lib/test-helpers.sh` (`mock_init`, `mock_bin`, `mock_log`, `assert_eq`, `assert_contains`...).
- `tests/apt-checks.sh` - read-only checks that every package OhMyDebn names exists.

Unit test rules:

- Nothing may touch the real system. Test a script by copying it with `sed`, pointing `/usr/share/ohmydebn/bin` (and any other absolute path) at the mock directory, and mocking `sudo`, `apt`, `dpkg` and friends. `install.sh` and some scripts read `OHMYDEBN_TEST_*` overrides (`OS_RELEASE`, `APT_DIR`, `SKIP_CONFIG`, `SYSTEMD_DIR`...) for paths that can't be patched.
- Always give the script under test its stdin: `</dev/null`, or the answers it should read. Inherited stdin can hang the suite.
- New behavior gets a test. A bug fix gets a test that fails without the fix; check that it does.
- Never run `install.sh`, `ohmydebn-update` or an installer on your own machine to try a change. Test real runs in a VM.

## Script conventions

- `#!/bin/bash` and `set -euo pipefail` for new scripts, two-space indentation.
- Comments explain why, and this codebase is generous with them: follow the surrounding density, and keep a comment true when you change the code under it.
- Section headings in terminal output come from `ohmydebn-headline`.
- Naming, for an app `<app>`: `ohmydebn-<app>` (opens it, installing first if needed), `-install`, `-remove`, `-run` (the payload inside a terminal window), `-cli` (runs in the current terminal), `-gui`, `-tiled`.
- Installers:
  - check `dpkg -s` first, and do nothing if the package is already installed
  - ask "Press Enter to continue or Ctrl-C to cancel." before changing anything, unless called with `--skip-prompt`, which means "part of an install or automation: ask nothing"
  - run `sudo /usr/bin/apt update` before `apt install`
  - pin any third-party apt repo to its own packages in `/etc/apt/preferences.d/`, and have the `-remove` script delete the same pin file
- Any yes/no question that follows "Press Enter" defaults to No (`[y/N]`), so a reflexive second Enter changes nothing.
- A new package dependency goes in exactly one place: `install/packaging/dependencies.sh`, `install/packaging/power-user.sh`, or the `ohmydebn` package's `--depends` in `ohmydebn-package-build/build-package-ohmydebn.sh`.
- Don't count on apt Recommends being installed: MX Linux disables them. Install anything you need explicitly.
- Detect behavior at runtime rather than by distro name where you can: for example, check `/run/systemd/system` for systemd, and ask apt whether a package exists.

## The menu

`bin/ohmydebn-menu` builds each menu with `menu "Title" "icon  Label\n..."` and a `case` on the result. `bin/ohmydebn-menu-tree` builds the search index by parsing the literal text of every `show_*_menu` function, so:

- Each item needs a matching `case` arm, and each arm a matching item.
- A list built at runtime (such as Setup > Defaults > Agent, which shows what's installed) must live in a function not named `show_*_menu`, and must branch with `if`/`elif`, not `case`.
- Keep labels short. The longest are about 40 characters including the icon, and longer ones don't fit.
- Privileged actions run in a terminal via `present_terminal "Title" "command"`.

## Windows and tiling

A launcher that opens a terminal window passes `--title`, and `config/tile-rules.json` places windows by `wmClass` plus an optional title regex. `wmClass` is the WM_CLASS class (the second string `xprop WM_CLASS` prints) and must match exactly.

## Checklists

### Adding an AI tool

1. If OhMyDebn packages it, a build script in `ohmydebn-package-build`. Turn off the app's self-updater: apt updates it.
2. `bin/ohmydebn-<name>`, `-install`, `-remove`, and `-run`/`-cli` for terminal tools. The installer asks `ohmydebn-ai-set-default --ask <name> || true` unless `--skip-prompt`.
3. Add the name to `ohmydebn-ai-set-default` (the name list, `display_name` and `package_of`), `ohmydebn-ai`, `ohmydebn-ai-cli`, and the doctor's valid-name list.
4. An Apps > AI item in `bin/ohmydebn-menu`, which only opens the tool.
5. A zsh alias in `install/config/zsh.sh` (with its own state marker), a `tile-rules.json` rule for its window, and a line in `bin/ohmydebn-pkg-remove-all-optional`.
6. The consistency lists (`AI_INSTALLER_TO_NAME`, `TITLE_OWNERS`), a `tests/unit/test-ohmydebn-<name>.sh`, and the name in the AI dispatch, zsh, doctor and removal tests.
7. If T3 Code should find it, a link in the T3 Code package's `agent-bin`.

### Supporting another distro

1. Find out what it actually reports: `/etc/os-release`, `/etc/apt/sources.list.d/`, the login manager. Derivatives vary: MX Linux reports itself as Debian 13, while Ubuntu derivatives report their own `ID` with `ID_LIKE=ubuntu`.
2. The distro check in `install.sh`, the supported list in its warning text, and the same check in `bin/ohmydebn-doctor`.
3. The apt-sources step in `install.sh` must leave the distro's own sources alone.
4. A case in `tests/unit/test-install-distro-detection.sh` using the distro's real `os-release`.
5. `installation.md` and `requirements.md` in `ohmydebn-docs`, then test the whole install in a VM.

### Theming another app

Add an `ohmydebn-theme-set-<app>` hook, call it from `bin/ohmydebn-theme-set`, and add it to the stub list in `tests/unit/test-theme-set-staging.sh`. A hook does nothing when its app isn't installed, writes files atomically (temporary file, then rename), and never replaces a setting the user chose themselves.

## Release notes

Every user-visible change gets a line under the upcoming version in `ohmydebn-docs/docs/release-notes.md`, written for end users: what they see or gain, in plain language, with no script names, paths or internals. Sections are New, Improvements, Fixes and Updated components. An updated component is just its name and new version.

## Release checklist

Work through this before every release, in order. The sibling repositories are assumed to be checked out next to this one (`../ohmydebn-package-build`, `../ohmydebn-docs`). Fix what's clearly correct to fix. For anything that implies a design decision (removing code nothing calls vs. wiring it up, changing a behavior users may rely on), stop and ask the maintainer rather than guessing.

1. **Confirm the version.** `VERSION` must match the upcoming section of `../ohmydebn-docs/docs/release-notes.md`, and that section is the release being prepared.
2. **Check the release notes against what actually changed.** Read every commit since the last release tag (`git log v<last>..HEAD`) in this repo, `../ohmydebn-package-build` and `../ohmydebn-docs`. Every user-visible change needs a line, in end-user language, and nothing may be listed that didn't ship. Every "Updated components" version must match the build script's `VERSION` in `../ohmydebn-package-build` and what the testing repo actually serves (`reprepro -b ../ohmydebn-packages-testing list trixie <package>`).
3. **Verify the docs against the source, not against themselves.** Go through every page of `../ohmydebn-docs/docs/`, plus `AGENTS.md`, `README.md` and `config/ohmydebn-skill/SKILL.md`. Check each claim (menu paths, hotkeys, command names, file paths, supported distros, what a feature does) by reading the code that implements it: `bin/ohmydebn-menu`, `install/keybinding/keybinding-custom.txt`, the scripts themselves. Confirming that a name still exists is not enough; read what the function does now.
4. **Check that every new feature is documented, not just that nothing documented is false.** For each item in the release's New and Improvements sections, confirm the matching docs page explains how to use it. A feature can ship with only a release-notes line and no how-to anywhere.
5. **Check the supported-distro list agrees everywhere it appears:** `install.sh`'s distro check and its warning text, `bin/ohmydebn-doctor`, and `installation.md`, `requirements.md`, `faq.md` and `index.md` in the docs.
6. **Review the whole tree, not just what changed since the last release**, for spelling and grammar errors, logic bugs, security issues, usability problems, readability, orphaned code, and code that needs refactoring. Issues introduced several releases ago are just as worth catching. In particular:
   - Security: unquoted variables, `sudo` calls broader than needed, downloads without verification, third-party apt repos without a pin, temporary files in predictable places, files written world-writable.
   - Usability: prompts and messages that are unclear or inconsistent, questions whose default isn't No, menu labels longer than about 40 characters.
   - Orphaned code: `bin/` scripts that no menu entry, keybinding, other script or doc refers to; functions nothing calls; comments that describe code that has since changed or been removed.
7. **Run the full test suite:** `tests/run.sh` with the apt checks included. Everything must pass. Then run `mkdocs build --strict` in `../ohmydebn-docs`.
8. **Check the package side.** In `../ohmydebn-package-build`, confirm every build script changed since the last release has been built into the testing repo. Compare the testing and stable repos (`reprepro -b <repo> list trixie` for each) and account for every difference: each one must be something this release intends to ship. `upload-to-repo-stable.sh` publishes everything in `../ohmydebn-packages-staging`, so nothing unintended may be sitting there.
9. **List what needs testing in a VM.** For each change, which supported distros it affects and what to try. The maintainer runs these; an agent can't. Include a fresh install and an update from the previous release.
10. **Clean up.** Remove stray temporary files and directories left in any of the three repos by agent sandboxes or test runs, and confirm `git status` in each shows only intended changes.

The maintainer then does the release itself: merges `dev` into `main` in this repo and the docs repo, builds the `ohmydebn` package from the clean release commit, promotes everything to stable with `upload-to-repo-stable.sh`, purges the Cloudflare cache if any republished file kept its name, tags `v<version>`, and publishes the GitHub release.
