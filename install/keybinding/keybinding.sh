#!/bin/bash

STATE_DIR=~/.local/state/ohmydebn-config
KEYBINDING_STATE=$STATE_DIR/keybinding-20260910

if [ ! -f $KEYBINDING_STATE ]; then
  /usr/share/ohmydebn/bin/ohmydebn-headline "Updating keybindings"

  KEYBINDING_DIR=/usr/share/ohmydebn/install/keybinding
  KEYBINDING_CINNAMON=$KEYBINDING_DIR/keybinding-cinnamon.txt
  KEYBINDING_CUSTOM=$KEYBINDING_DIR/keybinding-custom.txt

  # gsettings keys can be renamed/removed between Cinnamon versions (e.g.
  # "switch-input-source" no longer exists on Cinnamon 6.4+, which every
  # default install is now on - so this isn't a rare edge case, it's the
  # normal path, hence fully silent rather than a warning). `eval`ing a
  # failing `gsettings set` under the caller's `set -e`, from inside a
  # sourced function, can trip a bash bug ("pop_var_context: head of
  # shell_variables not a function context") that aborts the whole install.
  # `|| true` keeps the function's own exit status 0 so one missing key
  # doesn't take down the rest of the install; redirecting the eval's own
  # stdout/stderr swallows gsettings' own "No such key ..." message too,
  # not just the warning line that used to follow it - there's nothing an
  # end user could do about a Cinnamon schema not having a given key
  # anyway, so neither line is actionable enough to justify showing on
  # every single default install.
  function keybinding-cinnamon() {
    local CMD SCHEMA
    echo "$4"
    # An empty first argument targets the root
    # org.cinnamon.desktop.keybindings schema itself - some keys (e.g.
    # looking-glass-keybinding) live there directly, not under a
    # sub-schema like .wm or .media-keys.
    SCHEMA="org.cinnamon.desktop.keybindings"
    if [ -n "$1" ]; then
      SCHEMA="$SCHEMA.$1"
    fi
    CMD="gsettings set $SCHEMA $2 \"$3\""
    eval "$CMD" >/dev/null 2>&1 || true
  }

  function keybinding-custom() {
    local GSETTINGS1 GSETTINGS2 GSETTINGS3
    echo "$5"
    GSETTINGS1="gsettings set org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom-$1/ name \"$2\""
    GSETTINGS2="gsettings set org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom-$1/ command \"$3\""
    GSETTINGS3="gsettings set org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom-$1/ binding \"$4\""
    eval "$GSETTINGS1" || echo "Warning: skipped custom keybinding $1 name" >&2
    eval "$GSETTINGS2" || echo "Warning: skipped custom keybinding $1 command" >&2
    eval "$GSETTINGS3" || echo "Warning: skipped custom keybinding $1 binding" >&2
  }

  # The stock slots, as keybinding-custom.txt numbers them. Read rather
  # than counted: a removed stock hotkey leaves its number unused (34,
  # Antigravity, since 4.15.0), and counting lines would then list a slot
  # that isn't set and leave out the last one.
  STOCK_SLOTS=$(awk '$1 == "keybinding-custom" {print $2}' $KEYBINDING_CUSTOM)
  CUSTOM_KEYBINDING_MAX=$(sort -n <<<"$STOCK_SLOTS" | tail -1)
  CUSTOM_IDS=""
  for i in $STOCK_SLOTS; do
    CUSTOM_IDS+="'custom-$i', "
  done
  # Keep whatever else is already in the list - shortcuts the user added in
  # Cinnamon Settings (custom0, custom1, ...: no hyphen, Cinnamon's own
  # naming) and the custom-1000+ slots ohmydebn-keybindings-apply manages -
  # instead of truncating the list to the stock slots, which used to make
  # every user-added shortcut vanish from Settings on each keybinding refresh.
  # Cinnamon Settings' transient "__dummy__" entry is dropped, and so is a
  # stock slot that's no longer in the file (custom-34).
  CUSTOM_EXISTING=$(gsettings get org.cinnamon.desktop.keybindings custom-list 2>/dev/null | grep -oP "'[^']*'" | tr -d "'" || true)
  for existing in $CUSTOM_EXISTING; do
    [ "$existing" = "__dummy__" ] && continue
    if [[ "$existing" =~ ^custom-([0-9]+)$ ]] && [ "${BASH_REMATCH[1]}" -le "$CUSTOM_KEYBINDING_MAX" ]; then
      continue
    fi
    CUSTOM_IDS+="'$existing', "
  done
  CUSTOM_IDS="${CUSTOM_IDS%, }"

  # Update all keybindings and sort the output for display
  (
    # shellcheck source=keybinding-cinnamon.txt
    source "$KEYBINDING_CINNAMON"
    # shellcheck source=keybinding-custom.txt
    source "$KEYBINDING_CUSTOM"
  ) | grep -v "Removing" | sort

  # Publish custom-list AFTER the slots above, and twice. Cinnamon only
  # re-reads its custom shortcuts when custom-list itself changes
  # (js/ui/keybindings.js listens to changed::custom-list, not to the
  # per-slot name/command/binding keys), so writing the list first and the
  # slots after - as this used to - left Cinnamon holding the old bindings,
  # which is why a Cinnamon restart used to be scheduled here. Writing it
  # once with Cinnamon Settings' own transient "__dummy__" entry appended
  # and then without guarantees the value changes even when the set of
  # slots is identical to last time - the same trick Cinnamon Settings
  # uses when you add a shortcut. No restart needed for the rest either:
  # the wm keys are watched live by Muffin (verified with a real keypress
  # after a live change), media-keys has a "changed" handler in the same
  # keybindings.js, and looking-glass-keybinding has its own
  # changed:: handler in lookingGlass.js.
  gsettings set org.cinnamon.desktop.keybindings custom-list "[$CUSTOM_IDS, '__dummy__']" || echo "Warning: could not write custom-list" >&2
  gsettings set org.cinnamon.desktop.keybindings custom-list "[$CUSTOM_IDS]" || echo "Warning: could not write custom-list" >&2

  echo "You can see all keybindings by pressing Super + K"

  # Tells ohmydebn-keybindings-apply below that the stock slots were just
  # rewritten, so the user's own keybindings must go back on top even if their
  # file hasn't changed since they were last applied.
  export OHMYDEBN_KEYBINDINGS_STOCK_APPLIED=1

  mkdir -p $STATE_DIR
  touch $KEYBINDING_STATE
fi

# Stock keybindings renamed without a new marker above, so installs from
# before still show the old name in Cinnamon's keyboard settings: Super + K
# ("Hotkeys", renamed in 4.9.0), and Gmail and Cloudflare WARP (4.11.0).
# Rename just those, rather than bumping the marker, which would rewrite
# every stock keybinding - and only while the slot still runs what
# OhMyDebn put there, so a slot a user gave another job keeps the name
# they gave it. Runs on every update and changes nothing once renamed.
# rename_stock_keybinding <slot> <old name> <new name> <part of its command>
rename_stock_keybinding() {
  local slot="org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom-$1/"
  if [ "$(gsettings get "$slot" name 2>/dev/null)" = "'$2'" ] &&
    [[ "$(gsettings get "$slot" command 2>/dev/null)" == *"$4"* ]]; then
    gsettings set "$slot" name "$3" || true
  fi
}
rename_stock_keybinding 4 "Hotkeys" "Keybindings" "ohmydebn.org/hotkeys"
rename_stock_keybinding 2 "GMail" "Gmail" "https://mail.google.com"
rename_stock_keybinding 43 "Cloudflare Warp" "Cloudflare WARP" "ohmydebn-cloudflare-warp"

# Stock keybindings added since the marker above, for the same reason as
# the renames: bumping it would rewrite every stock keybinding. Installs
# from before get just the new slot, as keybinding-custom.txt has it, once:
# its own marker (keybinding-add-<slot>) then keeps it from coming back
# after the user removes it in Cinnamon's settings. A new install already
# has the slot from the full pass above, and only gets the marker.
# Console (Super + the key left of 1) came in 4.15.0.
# add_stock_keybinding <slot>
add_stock_keybinding() {
  local list line marker="$STATE_DIR/keybinding-add-$1"
  local slot="org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom-$1/"
  local -a fields
  [ -f "$marker" ] && return 0
  list=$(gsettings get org.cinnamon.desktop.keybindings custom-list 2>/dev/null) || return 0
  # Only a list gsettings actually printed: anything else (no session bus,
  # a schema that isn't there) leaves it alone, unmarked, for the next
  # update to try again rather than guessing.
  [[ "$list" == "["*"]" || "$list" == "@as []" ]] || return 0
  mkdir -p "$STATE_DIR"
  if [[ "$list" == *"'custom-$1'"* ]]; then
    touch "$marker"
    return 0
  fi
  line=$(grep "^keybinding-custom $1 " /usr/share/ohmydebn/install/keybinding/keybinding-custom.txt) || return 0
  # The line's own quoting gives the fields: slot, name, command, binding
  # and the description printed below.
  eval "fields=(${line#keybinding-custom })"
  gsettings set "$slot" name "${fields[1]}" || return 0
  gsettings set "$slot" command "${fields[2]}" || return 0
  gsettings set "$slot" binding "${fields[3]}" || return 0
  # Appended, with the same "__dummy__" toggle as above so Cinnamon
  # reloads its custom shortcuts.
  list="${list#@as }"
  list="${list%]}"
  [[ "$list" == "[" ]] || list+=", "
  gsettings set org.cinnamon.desktop.keybindings custom-list "${list}'custom-$1', '__dummy__']" || return 0
  gsettings set org.cinnamon.desktop.keybindings custom-list "${list}'custom-$1']" || return 0
  touch "$marker"
  echo "${fields[4]}"
}
add_stock_keybinding 48

# Stock keybindings removed since the marker above, for the same reason:
# installs from before still have the slot in their list, running a
# command that's gone. Each is taken out of the list once, and only while
# it still runs what OhMyDebn put there, so a slot the user gave another
# job keeps working. Its number is never reused. Its own marker
# (keybinding-remove-<slot>) is set once it's out or was never there, and
# not when gsettings prints no list, so the next update tries again.
# Antigravity (Ctrl + Super + G) went in 4.15.0.
# remove_stock_keybinding <slot> <part of its command>
remove_stock_keybinding() {
  local list marker="$STATE_DIR/keybinding-remove-$1"
  local slot="org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/custom-$1/"
  [ -f "$marker" ] && return 0
  list=$(gsettings get org.cinnamon.desktop.keybindings custom-list 2>/dev/null) || return 0
  [[ "$list" == "["*"]" || "$list" == "@as []" ]] || return 0
  mkdir -p "$STATE_DIR"
  if [[ "$list" != *"'custom-$1'"* ]] ||
    [[ "$(gsettings get "$slot" command 2>/dev/null)" != *"$2"* ]]; then
    touch "$marker"
    return 0
  fi
  list="${list#@as }"
  list="${list//"'custom-$1', "/}"
  list="${list//", 'custom-$1'"/}"
  list="${list//"'custom-$1'"/}"
  # The same "__dummy__" toggle as above, so Cinnamon reloads its custom
  # shortcuts.
  if [[ "$list" == "[]" ]]; then
    gsettings set org.cinnamon.desktop.keybindings custom-list "['__dummy__']" || return 0
  else
    gsettings set org.cinnamon.desktop.keybindings custom-list "${list%]}, '__dummy__']" || return 0
  fi
  gsettings set org.cinnamon.desktop.keybindings custom-list "$list" || return 0
  gsettings reset-recursively "$slot" 2>/dev/null || true
  touch "$marker"
}
remove_stock_keybinding 34 "ohmydebn-antigravity"

# The user's own keybindings (~/.config/ohmydebn/keybindings.txt), layered on
# top of the stock ones. Outside the state gate on purpose: it has to run when
# the user's file changed even though the stock keybindings didn't. It gates itself
# on the file's hash (and on the flag above), so on a normal update with
# nothing changed it exits silently. A separate process rather than a
# sourced script, and `|| true`, so nothing in the user's file can abort the
# install under the caller's `set -e`. Like the stock pass above it makes
# Cinnamon reload live via the custom-list toggle - no restart.
/usr/share/ohmydebn/bin/ohmydebn-keybindings-apply --from-install || true
