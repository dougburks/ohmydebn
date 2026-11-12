"""GLib calls whose home moved between the PyGObject versions OhMyDebn's
distros ship.

unix_signal_add() is GLib.unix_signal_add(), which newer PyGObject (Python
3.14's, on Linux Mint 27) still runs but warns about on every start -
"PyGIDeprecationWarning: GLib.unix_signal_add is deprecated; use
GLibUnix.signal_add instead" - while older PyGObject (Debian 13's 3.50,
Mint 22's) has no GLibUnix.signal_add at all: Debian 13 has a GLibUnix
typelib without it, Mint 22 no GLibUnix. So the new call where it exists,
else the old one. Both take (priority, signum, handler) and return the
source ID."""

import gi
from gi.repository import GLib


def _find_signal_add():
    try:
        gi.require_version("GLibUnix", "2.0")
        from gi.repository import GLibUnix
        return GLibUnix.signal_add
    except (ImportError, ValueError, AttributeError):
        return GLib.unix_signal_add


unix_signal_add = _find_signal_add()
