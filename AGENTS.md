# Agent Configuration and Management

## ClipboardSync Background Service (macOS)

The `clipboard_monitor.rb` script is configured to run automatically in the background on macOS using `launchd` as a Launch Agent. This ensures it starts on login and keeps running.

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
    (This was executed automatically by the agent to start the service.)

*   **Unload (Stop the service and prevent it from starting on next login):**
    ```bash
    launchctl unload ~/Library/LaunchAgents/com.cgenco.clipboardsync.plist
    ```

*   **Start (If unloaded, load and run immediately):**
    ```bash
    launchctl start com.cgenco.clipboardsync
    ```

*   **Stop (If loaded, stop immediately without unloading):**
    ```bash
    launchctl stop com.cgenco.clipboardsync
    ```

*   **Restart (Recommended way to apply changes to the .plist file or restart the script):**
    ```bash
    launchctl unload ~/Library/LaunchAgents/com.cgenco.clipboardsync.plist
    launchctl load ~/Library/LaunchAgents/com.cgenco.clipboardsync.plist
    ```
    *Note: A simple `launchctl stop` followed by `launchctl start` may not fully reload the configuration.*

*   **Check Status:**
    ```bash
    launchctl list | grep com.cgenco.clipboardsync
    ```

**Troubleshooting:**
Check the log files at `/tmp/clipboard_sync.log` and `/tmp/clipboard_sync.err` for any errors or output from the script.
