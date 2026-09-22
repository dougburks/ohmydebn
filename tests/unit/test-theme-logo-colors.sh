#!/bin/bash
#
# Unit tests for bin/ohmydebn-theme-logo-colors (the theme -> logo palette
# shaper) and the two logo scripts that consume it: ohmydebn-logo passes
# the palette to ttfx's rain effect, ohmydebn-show-logo tints toilet's
# output with the accent. toilet/ttfx/clear are mocked and HOME is a
# scratch dir, so nothing here draws on a real terminal or touches the
# real branding files.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COLORS="$REPO_ROOT/bin/ohmydebn-theme-logo-colors"
source "$REPO_ROOT/tests/lib/test-helpers.sh"

echo "=== ohmydebn-theme-logo-colors / ohmydebn-logo / ohmydebn-show-logo ==="

TTFX_DEFAULT_RAIN="00315C 004C8F 0075DB 3F91D9 78B9F2 9AC8F5 B8D8F8 E3EFFC"

# value_of <key> <output>
value_of() { printf '%s\n' "$2" | sed -n "s/^$1=//p"; }

# --- a full theme: gradient is accent/blue/cyan, rain climbs from a bg-mix to the foreground ---
SCRATCH=$(mktemp -d)
cat >"$SCRATCH/colors.toml" <<'EOF2'
mode = "dark"
accent = "#7d82d9"
background = "#060B1E"
foreground = "#ffcead"
blue = "#7d82d9"
cyan = "#a3bfd1"
magenta = "#c89dc1"
EOF2
OUT=$(bash "$COLORS" "$SCRATCH/colors.toml")
assert_eq "full theme: gradient is accent, blue, cyan - de-duplicated (blue == accent here), no '#'" \
  "7d82d9 a3bfd1" "$(value_of gradient "$OUT")"
assert_eq "full theme: accent reported lowercase without '#'" "7d82d9" "$(value_of accent "$OUT")"
assert_eq "full theme: accent as R;G;B for a truecolor escape" "125;130;217" "$(value_of accent_rgb "$OUT")"
RAIN=$(value_of rain "$OUT")
assert_eq "full theme: rain has 8 stops (4 bg-mixes, accent, blue, cyan, foreground) minus duplicates" \
  "7" "$(wc -w <<<"$RAIN")"
assert_eq "full theme: rain ends on the foreground" "ffcead" "${RAIN##* }"
assert_contains "full theme: rain passes through the accent" " $RAIN " " 7d82d9 "
rm -rf "$SCRATCH"

# --- the mixing math, on values that are easy to check by hand ---
SCRATCH=$(mktemp -d)
printf 'accent = "#ffffff"\nbackground = "#000000"\n' >"$SCRATCH/colors.toml"
RAIN=$(value_of rain "$(bash "$COLORS" "$SCRATCH/colors.toml")")
assert_eq "mix: white accent over black bg gives 20/40/60/80% greys then white" \
  "333333 666666 999999 cccccc ffffff" "$RAIN"
assert_eq "mix: gradient with only an accent is just the accent" \
  "ffffff" "$(value_of gradient "$(bash "$COLORS" "$SCRATCH/colors.toml")")"
rm -rf "$SCRATCH"

# --- fallbacks: no file, or a file without an accent, yields ttfx's stock palette ---
OUT=$(bash "$COLORS" /nonexistent/colors.toml)
assert_eq "no theme file: ttfx default rain" "$TTFX_DEFAULT_RAIN" "$(value_of rain "$OUT")"
assert_eq "no theme file: ttfx default gradient" "488bff b2e7de 57eaf7" "$(value_of gradient "$OUT")"
assert_eq "no theme file: accent_rgb still usable" "72;139;255" "$(value_of accent_rgb "$OUT")"
SCRATCH=$(mktemp -d)
printf 'background = "#000000"\nforeground = "#ffffff"\n' >"$SCRATCH/colors.toml"
assert_eq "no accent key: ttfx default rain" "$TTFX_DEFAULT_RAIN" "$(value_of rain "$(bash "$COLORS" "$SCRATCH/colors.toml")")"
printf 'accent = "not-a-color"\n' >"$SCRATCH/colors.toml"
assert_eq "malformed accent: ttfx default rain" "$TTFX_DEFAULT_RAIN" "$(value_of rain "$(bash "$COLORS" "$SCRATCH/colors.toml")")"
rm -rf "$SCRATCH"

# --- ohmydebn-logo hands the palette to ttfx; ohmydebn-show-logo tints with the accent ---
mock_init
mock_bin toilet <<'EOF2'
#!/bin/bash
mock_log "toilet $*"
cat 2>/dev/null; echo "LOGO-TEXT"
EOF2
mock_bin ttfx <<'EOF2'
#!/bin/bash
mock_log "ttfx $*"
cat >/dev/null
EOF2
mock_bin clear <<'EOF2'
#!/bin/bash
exit 0
EOF2
SCRATCH_HOME=$(mktemp -d)
mkdir -p "$SCRATCH_HOME/.config/ohmydebn/current/theme"
printf 'accent = "#11aa22"\nbackground = "#000000"\nblue = "#3344ff"\n' >"$SCRATCH_HOME/.config/ohmydebn/current/theme/colors.toml"
for script in ohmydebn-logo ohmydebn-show-logo ohmydebn-logo-generate ohmydebn-theme-logo-colors; do
  sed "s#/usr/share/ohmydebn/bin#$MOCK_BIN#g; s#/usr/bin/ttfx#$MOCK_BIN/ttfx#g" "$REPO_ROOT/bin/$script" >"$MOCK_BIN/$script"
  chmod +x "$MOCK_BIN/$script"
done
HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-logo" </dev/null >/dev/null 2>&1
CALLS=$(cat "$MOCK_CALLS")
assert_contains "ohmydebn-logo: ttfx rain gets the theme's rain colors" "$CALLS" "ttfx rain --rain-colors "
assert_contains "ohmydebn-logo: ttfx rain gets the theme's gradient (accent then blue)" "$CALLS" "--final-gradient-stops 11aa22 3344ff"
assert_contains "ohmydebn-logo: the rain list climbs to the accent" "$CALLS" " 0e881b 11aa22 3344ff --final-gradient-stops"
assert_contains "ohmydebn-logo: still renders the branding name via toilet" "$CALLS" "toilet -f mono12 OhMyDebn"

: >"$MOCK_CALLS"
OUT=$(HOME="$SCRATCH_HOME" PATH="$(mock_path)" bash "$MOCK_BIN/ohmydebn-show-logo" 2>/dev/null)
assert_contains "ohmydebn-show-logo: opens a truecolor escape with the accent" "$OUT" $'\e[38;2;17;170;34m'
assert_contains "ohmydebn-show-logo: logo text follows" "$OUT" "LOGO-TEXT"
assert_contains "ohmydebn-show-logo: resets the color afterwards" "$OUT" $'\e[0m'
rm -rf "$SCRATCH_HOME"
mock_cleanup

test_summary
