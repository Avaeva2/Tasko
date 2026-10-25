#!/bin/sh
# Optional machine-specific SDK paths. This file contains no defaults tied to
# one developer's workstation.
if [ -f config/toolchain.local.sh ]; then
  . ./config/toolchain.local.sh
fi
