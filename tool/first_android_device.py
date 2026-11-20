"""Print the id of the first Android device in `flutter devices --machine` output (stdin).

Used by the Makefile's android targets. Prints nothing when there is none.
"""

import json
import sys

try:
    devices = json.load(sys.stdin)
except ValueError:
    devices = []
for device in devices:
    if str(device.get("targetPlatform", "")).startswith("android"):
        print(device["id"])
        break
