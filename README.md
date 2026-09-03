# AppMan

AppMan apps in the Omarchy Quattro bar: see what's installed, update it all
in one click, install a local `.AppImage` via file picker or drag-drop, and
remove apps per row.

```sh
omarchy plugin add https://github.com/Fruffel/omarchy-appman.git --enable
~/.config/omarchy/plugins/fruffel.appman/scripts/setup
```

The setup script installs the post-boot hook (quiet background upgrade) and
places the widget. Without it the widget still works, but nothing upgrades
at boot.

## Usage

- Left click opens the panel, Escape closes it.
- Middle click upgrades immediately, right click refreshes the list.
- **Update all** upgrades everything (`appman -u`, including AppMan's own
  self-sync) in a floating terminal.
- **Install**: type a path, hit **Browse…**, or drop an `.AppImage` onto the
  section. It runs `appman --launcher` on the file, which registers it in
  the app menu.
- **Remove** next to an app uninstalls it without asking (`appman -R`).

## Dependencies

- [AppMan](https://github.com/ivan-hc/AM) (`appman`) on `PATH`.
- `jq` for status bookkeeping.
- `curl` for the `appman-install-url` helper script.
- `omarchy-launch-floating-terminal-with-presentation` and
  `omarchy-notification-send` (ship with Omarchy, `notify-send` fallback).

## Privileges

Everything runs as your user. No sudo is used or needed: AppMan installs
into `~/Applications` and the plugin state lives under
`~/.local/state/omarchy/appman.json`. The only persistent system touch is
the post-boot hook copy at `~/.config/omarchy/hooks/post-boot.d/appman-update`.

## Configure

Values live on the bar entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
| --- | --- | --- |
| `pollMinutes` | `30` | How often to refresh the installed list (local only, no network) |
| `upgradeOnStart` | `true` | Quiet upgrade ~45s after the shell starts |
| `showWhenCurrent` | `true` | Keep the icon visible when there is nothing to do |

```sh
omarchy bar set fruffel.appman pollMinutes 60
omarchy bar move fruffel.appman --section center --after fruffel.brew-update
```

Note: AppMan has no dry-run outdated check — `appman -u` runs the updaters
for real — so the widget shows the installed count, not a pending-update
count. The poll only re-reads the local list.

## Helper scripts

The panel covers install-from-file and remove. The rest is in `scripts/`
for terminal use:

```sh
scripts/appman-install-db firefox
scripts/appman-install-extra Selene-Apps/file-analyzer file-analyzer [keyword]
scripts/appman-install-file ~/Downloads/app.AppImage
scripts/appman-install-url https://example.com/app.AppImage [appname]
scripts/appman-upgrade [--quiet] [--notify]
```

## Update

```sh
omarchy plugin update fruffel.appman
```

## Remove

```sh
omarchy plugin remove fruffel.appman --yes
rm -f ~/.config/omarchy/hooks/post-boot.d/appman-update
```

## License

[MIT](LICENSE)
