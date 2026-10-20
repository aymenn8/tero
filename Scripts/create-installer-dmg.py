#!/usr/bin/env python3
"""Create a branded Finder installer without scripting Finder or changing user settings."""
import argparse
from pathlib import Path
import plistlib
import subprocess
import tempfile
import os
import dmgbuild
from ds_store import DSStore


def build(app, output, root):
    app, output, root = Path(app).resolve(), Path(output).resolve(), Path(root).resolve()
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.aymenkadri.tero':
        raise ValueError('The public installer requires the production Tero bundle.')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    icon = app/'Contents/Resources'/f"{info['CFBundleIconFile'].removesuffix('.icns')}.icns"
    if not icon.is_file():
        raise ValueError('The application icon is missing.')
    background = output.parent/'installer-background.tiff'
    subprocess.run(['swift', str(root/'Scripts/generate-installer-background.swift'), str(background), str(root)], check=True)
    dmgbuild.build_dmg(str(output), 'Tero', settings={
        'format':'UDZO', 'filesystem':'HFS+', 'files':[str(app)],
        'symlinks':{'Applications':'/Applications'}, 'icon':str(icon),
        'background':str(background), 'window_rect':((180,180),(660,420)),
        'default_view':'icon-view', 'icon_locations':{'Tero.app':(170,225),'Applications':(490,225)},
        'icon_size':100, 'text_size':13, 'label_pos':'bottom',
        # Do not set FinderInfo on the signed app to hide its extension.
        'arrange_by':None,
        'show_status_bar':False, 'show_tab_view':False, 'show_toolbar':False,
        'show_pathbar':False, 'show_sidebar':False, 'show_icon_preview':False,
        'include_icon_view_settings':True, 'include_list_view_settings':False,
    })
    # Verify the actual image, not just the settings passed to the packager.
    with tempfile.TemporaryDirectory(prefix='tero-installer-check-') as mount:
        subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, str(output)], check=True, stdout=subprocess.DEVNULL)
        try:
            mounted = Path(mount)
            if not (mounted/'.VolumeIcon.icns').is_file() or os.readlink(mounted/'Applications') != '/Applications':
                raise ValueError('The installer icon or Applications link is missing.')
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(mounted/'Tero.app')], check=True)
            with DSStore.open(str(mounted/'.DS_Store'), 'r') as store:
                if store['Tero.app']['Iloc'] != (170,225) or store['Applications']['Iloc'] != (490,225):
                    raise ValueError('The installer icon layout is incorrect.')
                view = store['.']['icvp']
                if view['backgroundType'] != 2 or not view['backgroundImageAlias'] or view['iconSize'] != 100:
                    raise ValueError('The installer background or view settings are missing.')
        finally:
            subprocess.run(['hdiutil', 'detach', mount], check=True, stdout=subprocess.DEVNULL)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--root', required=True)
    args = parser.parse_args()
    build(args.app, args.output, args.root)
