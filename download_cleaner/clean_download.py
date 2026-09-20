import os
import stat
from pathlib import Path
import re
import time
import argparse

# UF_HIDDEN flag hides an item in Finder without renaming it (macOS `chflags hidden`).
# Original file names are preserved exactly on disk; only Finder visibility changes.
UF_HIDDEN = getattr(stat, 'UF_HIDDEN', 0x00008000)

parser = argparse.ArgumentParser()
parser.add_argument('--skip_date_check', default=False, dest='skip_date_check')
args = parser.parse_args()
SKIP_DATE_CHECK = bool(int(args.skip_date_check))

CURRENT_TIME = time.time() 
TIME_DIFFERENCE = 60 * 60 * 24 - 60 # 24 hours - 1 minute (to avoid processing files again.)

IGNORED_FILES = ['.DS_Store', '.localized', 'Thumbs.db', '.com.google.', 'var-www']

FOLDERS  = ['documents', 'sql', 'codes', 'media', 'credentials', 'programs', 'compressed', 'other']
OTHER_FOLDER = 'other'
extension_mapping = {
    'documents': ['.doc', '.docx','.pdf', '.txt', '.ods', '.xlr', '.xls', '.xlsx', '.key', '.odp', '.pps', '.ppt', '.pptx', '.csv', '.drawio', '.md'],
    'sql': ['.sql'],
    'codes': ['.html', '.xml', '.c', '.py', '.sh', '.js', '.ipynb', '.json', '.css', '.cpp', '.java', '.php'],
    'media': ['.ai', '.HEIC', '.bmp', '.gif', '.ico', '.jpeg', '.jpg', '.png', '.ps', '.psd', '.svg', '.h264', '.m4v', '.mkv', '.mov', '.mp4', '.mpg', '.mpeg', '.rm', '.swf', '.vob', '.wmv'],
    'programs': ['.dmg', '.apk', '.app'],
    'compressed': ['.rar', '.arj', '.deb', '.pkg', '.7z', '.rpm', '.tar.gz', '.z', '.zip', '.gz', '.bz2', '.xz', '.tar'],
}

extension_to_type = {ext: ftype for (ftype, extlist) in extension_mapping.items() for ext in extlist}

def get_destination(ext):
    global extension_to_type
    return extension_to_type.get(ext, OTHER_FOLDER)

def slugify(value):
    value = re.sub(r'[^\w\s-]', '', value).strip()
    value = re.sub(r'[-\s]+', '_', value)
    return value

def should_process_file(file):
    for ignored_file in IGNORED_FILES:
        if ignored_file in file.name or ignored_file in file.stem or file.name.startswith('.') or file.stem in ignored_file:
            return False

    if SKIP_DATE_CHECK:
        return True
    
    last_modified_time = file.stat().st_mtime
    time_difference = CURRENT_TIME - last_modified_time
    return time_difference < TIME_DIFFERENCE

def create_folders():
    for folder in FOLDERS:
        folder_path = downloads_path / folder
        if not folder_path.exists():
            folder_path.mkdir()

def hide_path(path):
    """Set the macOS UF_HIDDEN flag on a path without renaming it.
    The original name is kept exactly as-is; Finder simply won't show it."""
    try:
        current_flags = os.stat(path).st_flags
        if not (current_flags & UF_HIDDEN):
            os.chflags(path, current_flags | UF_HIDDEN)
    except (OSError, AttributeError) as e:
        # AttributeError: platform without chflags/st_flags (non-macOS).
        # OSError: permission/path issues -- skip rather than break the cron run.
        print("Could not hide:", path, "->", e)

def hide_media_contents():
    """Hide everything inside ~/Downloads/media (recursively) so the folder's
    contents are never visible in Finder. File names are left unchanged."""
    media_path = downloads_path / 'media'
    if not media_path.exists():
        return
    for root, dirs, files in os.walk(media_path):
        for name in list(dirs) + files:
            hide_path(os.path.join(root, name))

home_dir = Path.home()
downloads_path = home_dir / 'Downloads'
contents = downloads_path.iterdir()

contents = sorted(contents, key=lambda x: x.stat().st_mtime, reverse=True)
create_folders()

f: Path
for f in contents:
    if should_process_file(f):
        slug_name = slugify(f.stem)
        if f.is_dir():
            if f.name not in FOLDERS:
                print("Moving folder: ", f)
                print("Will be moved to: ", os.path.join(downloads_path, OTHER_FOLDER, slug_name))
                os.rename(f, os.path.join(downloads_path, OTHER_FOLDER, slug_name))


        elif f.is_file():
            extension = f.suffix
            slug_name = "{}{}".format(slug_name, extension)
            destination = get_destination(extension)
            print("Moving file: ", f)
            print("Will be moved to: ", os.path.join(home_dir, destination, slug_name))
            os.rename(f, os.path.join(downloads_path, destination, slug_name))

# Always ensure the media folder's contents stay hidden in Finder, even for
# files that were already moved on previous runs.
hide_media_contents()
