#!/usr/bin/env python3
"""
Vérifie que chaque chaîne visible a sa traduction française.

Ne regarde que les littéraux sans interpolation : une chaîne interpolée devient
une clé à format (« %@ », « %lld ») que ce script ne peut pas deviner de façon
fiable, et un faux positif qui casse la CI est pire qu'un trou détecté à l'œil.

    python3 Scripts/check-translations.py
"""

import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Noms propres et identifiants : ce sont des littéraux, pas des chaînes à traduire.
IGNORE = {
    "Cocker", "Homebrew", "Colima", "Docker CLI", "Docker Compose", "Docker Buildx",
    "English", "Français", "Architecture", "Images", "Volumes",
}

# L'À propos porte la licence et la mention de marque : elles restent en anglais.
SKIP_FILES = {"AboutView.swift"}

PATTERN = re.compile(
    r'(?:Text|Label|Button|Toggle|Section|Picker|LocalizedStringKey)\(\s*"([^"\\]+)"'
    r'|\.help\(\s*"([^"\\]+)"'
    r'|confirmationDialog\(\s*"([^"\\]+)"'
)


def translated_keys() -> set[str]:
    text = (ROOT / "Resources/fr.lproj/Localizable.strings").read_text()
    return set(re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', text, re.M))


def main() -> int:
    keys = translated_keys()
    missing: list[str] = []

    for path in sorted((ROOT / "Sources").rglob("*.swift")):
        if path.name in SKIP_FILES:
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if line.strip().startswith("//"):
                continue
            for groups in PATTERN.findall(line):
                for key in groups:
                    if not key or key in IGNORE or key in keys:
                        continue
                    if not re.search(r"[A-Za-z]", key):
                        continue
                    missing.append(f"{path.name}:{number}  {key}")

    if missing:
        print("Chaînes sans traduction française :", file=sys.stderr)
        for item in sorted(set(missing)):
            print(f"  {item}", file=sys.stderr)
        return 1

    print(f"✓ {len(keys)} traductions, aucune chaîne orpheline")
    return 0


if __name__ == "__main__":
    sys.exit(main())
