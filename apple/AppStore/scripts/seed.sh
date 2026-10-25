#!/bin/zsh
# Fresh install of the screenshot build on $1, with openly licensed books
# staged where the app carries over Chibi Manga's library on first launch.
set -e
D=$1
S=${STORE_WORK:?set STORE_WORK to the folder with raw, art, brand and seed}
APP=${APP:?set APP to a Release simulator build of Chek.app}
xcrun simctl bootstatus $D -b >/dev/null
xcrun simctl ui $D appearance light
xcrun simctl status_bar $D override --time "9:41" --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --wifiBars 3 --dataNetwork wifi
xcrun simctl uninstall $D run.chibi.manga 2>/dev/null || true
xcrun simctl install $D $APP
C=$(xcrun simctl get_app_container $D run.chibi.manga data)
mkdir -p "$C/Documents/imports"
cp $S/seed/* "$C/Documents/imports/"
python3 - "$C/Documents/imports" <<'PY'
import json, os, sys, time
folder = sys.argv[1]
now = time.time() - 978307200  # seconds since 2001
reading = {"Alice's Adventures in Wonderland.epub": (12, 600), "Pepper&Carrot Episode 8.cbz": (3, 1800), "The Secret Garden.epub": (20, 7200), "Brave Bora.cbz": (6, 20000), "Frankenstein.epub": (9, 40000)}
entries = []
for i, name in enumerate(sorted(os.listdir(folder))):
    if name.startswith('.'): continue
    page, ago = reading.get(name, (0, None))
    e = {"fileName": name, "currentPage": page}
    if ago: e["lastReadAt"] = now - ago
    entries.append(e)
json.dump(entries, open(os.path.join(folder, ".library.json"), "w"))
print(len(entries), "staged")
PY
xcrun simctl launch $D run.chibi.manga >/dev/null
