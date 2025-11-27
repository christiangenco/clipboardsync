# Clipboard Sync (MacOS -> Linux/Wayland)

A lightweight Ruby script to monitor your MacOS clipboard and intelligently sync the content to a remote Linux machine running Wayland (using `wl-clipboard`).

## Features

- **Real-time Monitoring:** Polls the MacOS clipboard for changes every 0.5s.
- **Smart Detection:** Identifies if you've copied a File, Image, Rich Text, or Plain Text.
- **Wayland Compatible:** Automatically detects the correct Wayland environment variables (`WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`) on the remote machine so SSH commands work seamlessly.
- **Non-Blocking:** Sync operations happen in background threads, ensuring the monitor never freezes even if the network is slow.

## Prerequisites

**On MacOS (Source):**
- Ruby
- SSH access to the remote machine (setup SSH keys for passwordless login).

**On Linux (Destination):**
- Wayland compositor (Sway, Hyprland, Gnome, etc.)
- `wl-clipboard` installed (`sudo apt install wl-clipboard` or `pacman -S wl-clipboard`).

## Configuration

Open `clipboard_monitor.rb` and edit the `REMOTE_HOST` constant at the top:

```ruby
class ClipboardSync
  REMOTE_HOST = "archy.local" # Change this to your Linux machine's hostname or IP
  # ...
end
```

## Usage

Run the script in your terminal:

```bash
ruby clipboard_monitor.rb
```

### Running in Background (macOS)

The `clipboard_monitor.rb` script can be configured to run automatically in the background on macOS using `launchd` as a Launch Agent. This ensures it starts on login and keeps running.

**How it works:**
A Launch Agent definition file (`com.cgenco.clipboardsync.plist`) is placed in `~/Library/LaunchAgents/`. This file instructs `launchd` to execute the Ruby script. The script's standard output and errors are redirected to log files for debugging.

**Configuration Details:**
*   **Agent Label:** `com.cgenco.clipboardsync`
*   **Program:** `/Users/cgenco/.rbenv/shims/ruby /Users/cgenco/projects/clipboardsync/clipboard_monitor.rb`
*   **Working Directory:** `/Users/cgenco/projects/clipboardsync`
*   **Logs:**
    *   Standard Output: `/tmp/clipboard_sync.log`
    *   Standard Error: `/tmp/clipboard_sync.err`

**Management Commands:**

*   **Load (Start on next login, or immediately if not running):**
    ```bash
    launchctl load ~/Library/LaunchAgents/com.cgenco.clipboardsync.plist
    ```

*   **Unload (Stop the service and prevent it from starting on next login):**
    ```bash
    launchctl unload ~/Library/LaunchAgents/com.cgenco.clipboardsync.plist
    ```

*   **Restart (Recommended way to apply changes to the .plist file or restart the script):**
    ```bash
    launchctl unload ~/Library/LaunchAgents/com.cgenco.clipboardsync.plist
    launchctl load ~/Library/LaunchAgents/com.cgenco.clipboardsync.plist
    ```

*   **Check Status:**
    ```bash
    launchctl list | grep com.cgenco.clipboardsync
    ```

## The "Best Fit" Strategy

Clipboards are messy. When you copy something on MacOS, the system often creates multiple representations of that same data simultaneously (e.g., a file copy creates a File URL, a file path string, and sometimes an icon image).

To prevent conflicts and ensure the most useful data arrives on your Linux machine, this script uses a **Strict Priority System** to sync only the single "best" format found.

### Priority Order:

1.  **📁 Files** (Highest Priority)
    -   **Why:** If you copy a file in Finder, you almost certainly want the actual file, not just the text path to it.
    -   **Action:** The script `scp`s the file to `~/Downloads/` on the remote machine and registers it as a file source.

2.  **🌈 Rich Text (HTML/RTF)**
    -   **Why:** Preserves formatting (bold, links, colors) which is harder to reconstruct from plain text.
    -   **Action:** Pipes the raw HTML or RTF content directly to `wl-copy` with the appropriate MIME type.

3.  **🖼️ Images**
    -   **Why:** Images are heavy. We check for them after files/rich text to avoid false positives (sometimes text apps put a small icon on the clipboard).
    -   **Action:** Saves the image to a temp PNG, `scp`s it, and pipes it to `wl-copy`.

4.  **📝 Plain Text** (Fallback)
    -   **Why:** The universal fallback. If it's not a file, fancy text, or an image, it's just text.
    -   **Action:** Simple string copy.

## Troubleshooting

**"Failed to connect to a Wayland server"**
This script attempts to auto-detect your remote Wayland socket using:
`export XDG_RUNTIME_DIR=/run/user/$(id -u); export WAYLAND_DISPLAY=$(cd $XDG_RUNTIME_DIR && ls wayland-[0-9]* ...)`

If this fails, ensure you are logged into the Wayland session on the remote machine and that `wl-copy` works locally there.