# Double Trouble

A native macOS app to run several isolated copies of **Claude Desktop** and
**Claude Code** side by side: one per account, one per client, work and personal.
Each environment gets its own login, settings and history, and its own icon, so
you can tell them apart in the Dock.

Double Trouble is an independent project. It is not affiliated with, endorsed by
or sponsored by Anthropic. "Claude" is a trademark of Anthropic, PBC, and is used
here only to say which apps this tool works with.

## Requirements

- macOS 14 or later, Apple Silicon
- [Claude Desktop](https://claude.ai/download) in `/Applications`, and/or
  [Claude Code](https://docs.claude.com/en/docs/claude-code) on your `PATH`

## Install

1. Download the `.dmg` from [Releases](../../releases) and drag **Double Trouble**
   into Applications.
2. The app is signed ad hoc, not notarized, so macOS blocks it the first time.
   Open it once, then go to **System Settings → Privacy & Security** and click
   **Open Anyway**. Or, in Terminal:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/Double Trouble.app"
   ```

## Claude Desktop environments

Each environment is a small launcher app, `Claude <Name>.app`, plus its own
profile folder in `~/.claude-instances/<id>`. From the app you can:

- create an environment: name, profile id, icon color, an optional badge (a dot
  with up to three letters in the bottom-right corner), and optionally a copy of
  your current Claude profile so it starts already signed in;
- rename it and change color and badge (the profile id never changes: it is the
  folder name);
- install the launcher in Applications, or drag its icon to the Dock;
- open it, or force quit it;
- see how much space the profile uses, and free the caches and the Cowork VM
  files (several GB, downloaded again when needed);
- delete it. The launcher goes to the Trash. The profile is only deleted if you
  tick the box and type its name, and it goes to the Trash too.

Profiles in `~/.claude-instances` without a launcher show up as well, so you can
give them one again.

### How it works

Claude Desktop is an Electron app: `--user-data-dir` points it at a separate
profile folder. When you click a launcher, it:

- focuses that environment's window if it has one;
- opens a new window if the environment is running without one (it never kills
  it: Claude may still be working on a reply);
- otherwise starts Claude on that profile.

To make the running app show the launcher's icon, Claude is started from a
per-environment copy of `Claude.app` in
`~/Library/Application Support/Double Trouble/Clones.noindex`. It is an APFS
clone, so it takes no extra space until the two diverge. The icon is set as a
Finder custom icon, which lives outside the code signature: Anthropic's
signature stays valid and the Keychain keeps working. The copy is refreshed when
Claude updates. If cloning is not possible, the launcher starts `Claude.app` as
is.

### Known limits

- A launcher you keep in the Dock and the running app are two separate icons
  (with the same look). The Dock merges them only when they are the same app,
  and the copy cannot pick its profile when started from the Dock.
- When Claude updates itself inside a copy, it restarts that copy without its
  profile. If Double Trouble is open, it puts it back on the right profile
  within a few seconds.
- Every copy is the same app to macOS, so `claude://` links (such as the
  browser sign-in) reach one instance only. Sign in to one environment at a
  time.

## Claude Code environments

Each environment is a config folder, `~/.claude-<name>`, used through
`CLAUDE_CONFIG_DIR`, plus a small command in `~/.local/bin/claude-<name>`. From
the app you can:

- create an environment, optionally copying `settings.json`, `CLAUDE.md`,
  agents, commands and skills from another one;
- see which account each environment is signed into;
- create the command for a config folder you already use, for example through a
  shell alias. The app finds aliases in fish, zsh and bash, and can turn them
  off for you: it comments out the line and keeps a backup of the file;
- copy the command, rename the environment, delete it (same protections as
  above).

Your main `~/.claude` is listed first and is never deleted.

## Privacy

Double Trouble makes no network requests and collects nothing. It reads and
writes only the folders listed above, your shell config files when you ask it
to turn off an alias, and the launchers it created.

## Build from source

The Xcode Command Line Tools are enough.

```bash
./scripts/build-app.sh          # checks + dist/Double Trouble.app + .zip
./scripts/build-app.sh --open   # same, then launches it
./scripts/make-dmg.sh           # builds, then dist/Double-Trouble-<version>.dmg (needs Python 3.10+)
swift run CoreChecks            # core checks only
```

The app is in English and Italian. The icon sources are in `Design/`.

## Credits

Double Trouble was inspired by two gists:

- [Multiple Claude Desktop instances on macOS](https://gist.github.com/aoxborrow/5a3a0ac0aa37819cc19439b70a552221)
  by aoxborrow, which introduced color-coded launchers and the focus-or-launch
  behavior. Launchers created with its `make-claude-instance.sh` are recognized
  by the app.
- [Philipp Stracker's `--user-data-dir` technique](https://philippstracker.com/multiple-claude-instances/)
  ([gist](https://gist.github.com/stracker-phil/9f84927a556632c7f9cc06663b534f14)),
  which both build on.

No code from either gist is included: the launcher script and the icon
recoloring were written from scratch for this app.

## License

[MIT](LICENSE)
