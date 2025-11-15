#!/bin/bash

if [ "$UID" -eq 0 ]; then

  /opt/ohmydebn/bin/ohmydebn-headline "cat" "Looks like you're running as root.
 
Instead of running as root, you most likely want to 
run this as a normal user that has sudo privileges.

Press Enter if you are sure you want to continue as root
or Ctrl-c to cancel."

  read input
fi
