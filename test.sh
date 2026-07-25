#!/bin/bash
# Swift Testing wrapper for environments with only CommandLineTools (no Xcode).
# The Testing framework and its macro plugin ship with CommandLineTools but live
# off the default search paths, so we point swift test at them explicitly.
set -euo pipefail
exec swift test \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks/ \
  -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks/ \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib/ \
  "$@"
