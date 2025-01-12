import os
from pathlib import Path
import re
import time

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
    'compressed': ['.rar', '.arj', '.deb', '.pkg', '.7z', '.rpm'],
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

    last_modified_time = file.stat().st_mtime
    time_difference = CURRENT_TIME - last_modified_time
    return time_difference < TIME_DIFFERENCE

def create_folders():
    for folder in FOLDERS:
        folder_path = downloads_path / folder
        if not folder_path.exists():
            folder_path.mkdir()

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