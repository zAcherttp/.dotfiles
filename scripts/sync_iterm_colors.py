import subprocess
import plistlib
import os
import tempfile

def hex_to_iterm_color(hex_str, alpha=1.0):
    hex_str = hex_str.lstrip("#")
    r = int(hex_str[0:2], 16) / 255.0
    g = int(hex_str[2:4], 16) / 255.0
    b = int(hex_str[4:6], 16) / 255.0
    return {
        "Color Space": "sRGB",
        "Red Component": r,
        "Green Component": g,
        "Blue Component": b,
        "Alpha Component": alpha,
    }

vscode_dark_colors = {
    "Ansi 0 Color": hex_to_iterm_color("#000000"),
    "Ansi 1 Color": hex_to_iterm_color("#cd3131"),
    "Ansi 2 Color": hex_to_iterm_color("#0dbc79"),
    "Ansi 3 Color": hex_to_iterm_color("#e5e510"),
    "Ansi 4 Color": hex_to_iterm_color("#2472c8"),
    "Ansi 5 Color": hex_to_iterm_color("#bc3fbc"),
    "Ansi 6 Color": hex_to_iterm_color("#11a8cd"),
    "Ansi 7 Color": hex_to_iterm_color("#e5e5e5"),
    "Ansi 8 Color": hex_to_iterm_color("#666666"),
    "Ansi 9 Color": hex_to_iterm_color("#f14c4c"),
    "Ansi 10 Color": hex_to_iterm_color("#23d18b"),
    "Ansi 11 Color": hex_to_iterm_color("#f5f543"),
    "Ansi 12 Color": hex_to_iterm_color("#3b8eea"),
    "Ansi 13 Color": hex_to_iterm_color("#d670d6"),
    "Ansi 14 Color": hex_to_iterm_color("#29b8db"),
    "Ansi 15 Color": hex_to_iterm_color("#ffffff"),
    "Background Color": hex_to_iterm_color("#1e1e1e"),
    "Foreground Color": hex_to_iterm_color("#cccccc"),
    "Cursor Color": hex_to_iterm_color("#ffffff"),
    "Cursor Text Color": hex_to_iterm_color("#000000"),
    "Selection Color": hex_to_iterm_color("#264f78"),
    "Selected Text Color": hex_to_iterm_color("#ffffff"),
    "Bold Color": hex_to_iterm_color("#ffffff"),
}

try:
    p = subprocess.Popen(["defaults", "export", "com.googlecode.iterm2", "-"], stdout=subprocess.PIPE)
    out, _ = p.communicate()
    plist = plistlib.loads(out)
    bookmarks = plist.get("New Bookmarks", [])
    for b in bookmarks:
        for color_name, color_dict in vscode_dark_colors.items():
            b[color_name] = color_dict
            b[f"{color_name} (Dark)"] = color_dict
            b[f"{color_name} (Light)"] = color_dict
        b["Minimum Contrast"] = 0.35

    with tempfile.NamedTemporaryFile(suffix=".plist", delete=False) as tmp:
        plistlib.dump(plist, tmp)
        tmp_path = tmp.name

    subprocess.run(["defaults", "import", "com.googlecode.iterm2", tmp_path], check=True)
    os.unlink(tmp_path)
    print("✓ iTerm2 colors synchronized successfully.")
except Exception as e:
    print(f"Warning: Could not update iTerm2 defaults automatically: {e}")
