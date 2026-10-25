#!/usr/bin/env python3
"""Build the console upload package: exactly the files the manifest names, nothing else.

The folder also holds things the add-on does not ship -- tests, the README, the compass
artwork sources, local reference copies of other add-ons. Zipping the folder by hand sweeps
those in, and a package the console will not install is hard to tell apart from a bad build.
This writes PBsMiniMap.zip with the manifest, the files it lists (with $(language) expanded
to every lang file present) and nothing besides.

    python3 tools/package.py
"""
import os, re, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "PBsMiniMap"
MANIFEST = NAME + ".addon"

def listed_files():
    out = [MANIFEST]
    for raw in open(os.path.join(ROOT, MANIFEST), encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("##") or line.startswith(";"):
            continue
        if "$(language)" in line:
            pattern = re.escape(line).replace(re.escape("$(language)"), r"[A-Za-z]+")
            for found in sorted(os.listdir(os.path.join(ROOT, os.path.dirname(line)))):
                candidate = os.path.join(os.path.dirname(line), found)
                if re.fullmatch(pattern, candidate) and candidate not in out:
                    out.append(candidate)
            continue
        out.append(line)
    return out

def main():
    files = listed_files()
    missing = [f for f in files if not os.path.isfile(os.path.join(ROOT, f))]
    if missing:
        sys.exit("listed in the manifest but not on disk: " + ", ".join(missing))
    target = os.path.join(ROOT, NAME + ".zip")
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            z.write(os.path.join(ROOT, f), os.path.join(NAME, f))
    total = sum(os.path.getsize(os.path.join(ROOT, f)) for f in files)
    print("%s: %d files, %.1f KB uncompressed, %.1f KB zipped"
          % (os.path.basename(target), len(files), total / 1024,
             os.path.getsize(target) / 1024))
    for f in files:
        print("  %7.1f KB  %s" % (os.path.getsize(os.path.join(ROOT, f)) / 1024, f))

main()
