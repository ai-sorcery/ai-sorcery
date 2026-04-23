#!/bin/bash
# setup-terminal-tabs.sh — configure Terminal to open one tab per shared folder.
#
# Strategy: AppleWindowTabbingMode=always makes new Terminal windows appear
# as tabs. We use AppleScript "do script" from tart exec to create windows
# (which become tabs), and .zprofile uses a counter to cd each tab to the
# right project directory.
#
# Usage: setup-terminal-tabs.sh <VM_NAME> <dir1> <dir2> ...

set -euo pipefail

VM_NAME="$1"
shift
DEV_DIRS=("$@")

if [ ${#DEV_DIRS[@]} -eq 0 ]; then
  echo "No directories provided for Terminal tabs."
  exit 0
fi

NUM_EXTRA_TABS=$(( ${#DEV_DIRS[@]} - 1 ))
FIRST_DIR="${DEV_DIRS[0]}"

tart exec "$VM_NAME" defaults write -g AppleWindowTabbingMode -string always

CASE_ENTRIES=""
for i in "${!DEV_DIRS[@]}"; do
  if [ "$i" -gt 0 ]; then
    CASE_ENTRIES+="            $((i + 1))) cd ${DEV_DIRS[$i]} ;;
"
  fi
done

tart exec "$VM_NAME" bash -c "cat > \"\$HOME/.zprofile\" << 'PROFILEEOF'
export LANG=en_US.UTF-8
eval \"\$(/opt/homebrew/bin/brew shellenv)\"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
if which rbenv > /dev/null; then eval \"\$(rbenv init -)\"; fi
export PATH=\"/opt/homebrew/opt/node@24/bin:\$PATH\"

# --- cd to project based on tab number ---
if [ \"\$TERM_PROGRAM\" = \"Apple_Terminal\" ]; then
    TAB_COUNTER_FILE=\"/tmp/.terminal-tab-counter\"

    if mkdir /tmp/.terminal-tabs-lock 2>/dev/null; then
        echo \"1\" > \"\$TAB_COUNTER_FILE\"
        cd $FIRST_DIR
    else
        TAB_NUM=\$(cat \"\$TAB_COUNTER_FILE\" 2>/dev/null || echo \"0\")
        TAB_NUM=\$((TAB_NUM + 1))
        echo \"\$TAB_NUM\" > \"\$TAB_COUNTER_FILE\"

        case \$TAB_NUM in
$CASE_ENTRIES        esac
    fi
fi
PROFILEEOF"

tart exec "$VM_NAME" bash -c '
  killall -9 Terminal 2>/dev/null
  sleep 2
  rm -rf /tmp/.terminal-tabs-lock /tmp/.terminal-tab-counter
  rm -rf ~/Library/Saved\ Application\ State/com.apple.Terminal.savedState
  defaults write com.apple.Terminal NSQuitAlwaysKeepsWindows -bool false
'

tart exec "$VM_NAME" open -a Terminal
sleep 4

for (( i=1; i<${#DEV_DIRS[@]}; i++ )); do
  tart exec "$VM_NAME" osascript -e 'tell application "Terminal" to do script ""' 2>/dev/null
  sleep 2
done

echo "Terminal tabs configured."
