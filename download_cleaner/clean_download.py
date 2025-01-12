import os
from pathlib import Path
import re
import time


CURRENT_TIME = time.time() 
TIME_DIFFERENCE = 60 * 60 * 24  # 24 hours
IGNORED_FILES = ['.DS_Store']

FOLDERS  = ['documents', 'sql', 'codes', 'media', 'credentials', 'programs', 'compressed', 'other']
FOLDERS_FOLDER = 'other'
extension_mapping = {
                     'documents': ['.doc', '.docx','.pdf', '.txt', 
                                   '.ods', '.xlr', '.xls', '.xlsx', '.key',
                                   '.odp', '.pps', '.ppt', '.pptx', '.csv', '.drawio', '.md'],
                    'sql': ['.sql'],

                    'codes': ['.html', '.xml', '.c', '.py', '.sh', '.js', '.ipynb', '.json', '.css', '.cpp', '.java', '.php',],

                     'media': ['.ai', '.HEIC', '.bmp', '.gif', '.ico', '.jpeg', '.jpg',
                                  '.png', '.ps', '.psd', '.svg', '.h264', '.m4v',
                                '.mkv', '.mov', '.mp4', '.mpg', '.mpeg', '.rm',
                                '.swf', '.vob', '.wmv'],

                     'programs': ['.dmg', '.apk', '.app'],

                    'compressed': ['.rar', '.arj', '.deb', '.pkg', '.7z', '.rpm',],

                    }

extension_to_type = {ext: ftype for (ftype, extlist) in extension_mapping.items() for ext in extlist}

def get_destination(ext):
    global extension_to_type
    return extension_to_type.get(ext, 'other')

def slugify(value):
    value = re.sub(r'[^\w\s-]', '', value).strip()
    value = re.sub(r'[-\s]+', '_', value)
    return value

def should_process_file(file):
    if file.name in IGNORED_FILES or file.stem in IGNORED_FILES:
        return False
    
    last_modified_time = file.stat().st_mtime
    time_difference = CURRENT_TIME - last_modified_time
    return time_difference < TIME_DIFFERENCE

home_dir = Path.home()
downloads_path = home_dir / 'Downloads'
contents = downloads_path.iterdir()

print('Currnet time:', CURRENT_TIME)
    
contents = sorted(contents, key=lambda x: x.stat().st_mtime, reverse=True)

counter = 0
f: Path
for f in contents:
    counter += 1
    if counter > 5:
        break
    if should_process_file(f):
        print("Processing file", f)
        slug_name = slugify(f.stem)
        print("Slug name", slug_name)
        print("Renaming file to", slug_name)
        # print("Would do: os.rename(%s, %s)\n", f, os.path.join(home_dir, slug_name))
        

        if f.is_dir():
            print("directory")
            print(f)

            if f.name in FOLDERS:
                print(f"Folder {f.name} exists")
            else:
                print(f"Moving {f.name} to {FOLDERS_FOLDER}")
                print("Would do: os.rename(%s, %s)\n", f, os.path.join(home_dir, FOLDERS_FOLDER, slug_name))
                os.rename(f, os.path.join(home_dir, FOLDERS_FOLDER, slug_name))

        elif f.is_file():
            extension = f.suffix
            slug_name = "{}{}".format(slug_name, extension)
            print("File", f, 'has the extension', extension)
            destination = get_destination(extension)
            print("And will be moved to", os.path.join(home_dir, destination))
            print("Would do: os.rename(%s, %s)\n", f, os.path.join(home_dir, destination, slug_name))
            os.rename(f, os.path.join(home_dir, destination, slug_name))
