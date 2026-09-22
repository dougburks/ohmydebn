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

  # To create new custom keybindings, first specify how many custom keybindings we're going to load
  CUSTOM_KEYBINDING_TOTAL=$(cat $KEYBINDING_CUSTOM | wc -l)
  # Not `let CUSTOM_KEYBINDING_TOTAL--` - `let`/`((...))` exit non-zero when
  # the resulting expression value is 0, which would abort the whole install
  # under the caller's `set -e` if the custom-keybindings count were ever 0.
  # Plain arithmetic assignment doesn't have that pitfall.
  CUSTOM_KEYBINDING_TOTAL=$((CUSTOM_KEYBINDING_TOTAL - 1))
  CUSTOM_IDS=""
  for i in $(seq 0 $CUSTOM_KEYBINDING_TOTAL); do
    CUSTOM_IDS+="'custom-$i', "
  done
  # Keep whatever else is already in the list - shortcuts the user added in
  # Cinnamon Settings (custom0, custom1, ...: no hyphen, Cinnamon's own
  # naming) and the custom-1000+ slots ohmydebn-keybindings-apply manages -
  # instead of truncating the list to the stock slots, which used to make
  # every user-added shortcut vanish from Settings on each keybinding refresh.
  # Cinnamon Settings' transient "__dummy__" entry is dropped.
  CUSTOM_EXISTING=$(gsettings get org.cinnamon.desktop.keybindings custom-list 2>/dev/null | grep -oP "'[^']*'" | tr -d "'" || true)
  for existing in $CUSTOM_EXISTING; do
    [ "$existing" = "__dummy__" ] && continue
    if [[ "$existing" =~ ^custom-([0-9]+)$ ]] && [ "${BASH_REMATCH[1]}" -le "$CUSTOM_KEYBINDING_TOTAL" ]; then
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

# The user's own keybindings (~/.config/ohmydebn/keybindings.txt), layered on
# top of the stock ones. Outside the state gate on purpose: it has to run when
# the user's file changed even though the stock keybindings didn't. It gates itself
# on the file's hash (and on the flag above), so on a normal update with
# nothing changed it exits silently. A separate process rather than a
# sourced script, and `|| true`, so nothing in the user's file can abort the
# install under the caller's `set -e`. Like the stock pass above it makes
# Cinnamon reload live via the custom-list toggle - no restart.
/usr/share/ohmydebn/bin/ohmydebn-keybindings-apply --from-install || true
