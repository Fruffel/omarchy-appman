# AppMan

Bar widget for Omarchy Quattro that lists your [AppMan](https://github.com/ivan-hc/AM)
apps, updates them in one click, and integrates a local `.AppImage` via
file picker or drag-drop — without leaving the desktop.

AppMan has no cheap "check for updates" command (`appman -u` runs the
updaters for real), so this widget lists what is installed and lets you
update on demand, instead of pretending to know what is outdated.

## Install

```sh
git clone <this-repo> ~/Projects/omarchy-appman
ln -s ~/Projects/omarchy-appman ~/.config/omarchy/plugins/fruffel.appman
~/.config/omarchy/plugins/fruffel.appman/scripts/setup
```

## Usage

- The package icon stays in the bar with your installed-app count.
- Left click opens the panel. **Update all** runs the upgrade in a floating terminal.
- Middle click upgrades immediately.
- Right click refreshes the installed list.
- A post-boot hook upgrades apps quietly after the desktop starts and only
  notifies when something actually changed.

### Installing apps

From the panel: type a path, hit **Browse…**, or drag-drop an `.AppImage`
onto the install section. It runs `appman --launcher` on the file.

The other flows live in `scripts/` for the terminal:

```sh
scripts/appman-install-db firefox
scripts/appman-install-extra Selene-Apps/file-analyzer file-analyzer
scripts/appman-install-file ~/Downloads/app.AppImage
scripts/appman-install-url https://example.com/app.AppImage [appname]
```

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

## Remove

```sh
omarchy plugin disable fruffel.appman
rm -f ~/.config/omarchy/hooks/post-boot.d/appman-update
```

## Companion

Pairs with `fruffel.brew-update` (Homebrew from the bar) using the same
widget/hook conventions.
