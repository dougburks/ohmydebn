#!/usr/bin/python3
# Prints the argv a desktop file's Exec line launches, one argument per
# line, parsed the way GLib (and so Cinnamon) does it: the key file's
# string unescaping, then %% -> %, then shell-style argument splitting.
# Used by the launcher installer tests to check their quoting.
import sys

from gi.repository import GLib

keyfile = GLib.KeyFile()
keyfile.load_from_file(sys.argv[1], GLib.KeyFileFlags.NONE)
exec_line = keyfile.get_string("Desktop Entry", "Exec").replace("%%", "%")
ok, argv = GLib.shell_parse_argv(exec_line)
print("\n".join(argv))
