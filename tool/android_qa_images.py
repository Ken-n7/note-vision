#!/usr/bin/env python3
"""Copy QA photos into a recent Android album without changing source images.

Example (first image appears newest):
  python3 tool/android_qa_images.py --serial 6d718c9c --batch 2027 \
      /path/to/sparse.jpg /path/to/another.jpg

Requires adb, an unlocked authorized Android device, and MediaStore shell access.
Only copies in Pictures/NoteVisionQA are dated. Re-run to refresh their dates.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import pathlib
import re
import shlex
import subprocess
import time

ALBUM = '/sdcard/Pictures/NoteVisionQA'
MEDIA_ALBUM = '/storage/emulated/0/Pictures/NoteVisionQA'
URI = 'content://media/external/images/media'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--batch', required=True)
    parser.add_argument('photos', type=pathlib.Path, nargs='+')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9-]+', args.batch):
        parser.error('batch must contain only letters, numbers and hyphens')
    for photo in args.photos:
        if not photo.is_file() or photo.suffix.lower() not in ('.jpg', '.jpeg', '.png'):
            parser.error(f'expected an existing JPEG or PNG: {photo}')

    def adb(*command):
        result = subprocess.run(['adb', '-s', args.serial, *command],
                              check=True, capture_output=True, text=True)
        if 'Exception' in result.stderr or 'Error:' in result.stderr:
            raise SystemExit(result.stderr.strip())
        return result.stdout

    def shell(*command):
        return adb('shell', shlex.join(command)).strip()

    def query(path):
        return shell('content', 'query', '--uri', URI,
                     '--projection', '_id:_display_name:datetaken:date_modified:is_pending:width:height',
                     '--where', f"_data='{path}'")

    shell('mkdir', '-p', ALBUM)
    now = int(time.time())
    for index, photo in enumerate(args.photos):
        name = f'NVQA{args.batch}-{index + 1:02}{photo.suffix.lower()}'
        destination = f'{ALBUM}/{name}'
        media_path = f'{MEDIA_ALBUM}/{name}'
        digest = hashlib.sha256(photo.read_bytes()).hexdigest()
        exists = shell('sh', '-c', f'test -e {shlex.quote(destination)} && echo yes || true')
        if exists:
            existing = shell('sha256sum', destination).split()[0]
            if existing != digest:
                raise SystemExit(f'Refusing to overwrite a different existing photo: {destination}')
        else:
            adb('push', str(photo), destination)
        if shell('sha256sum', destination).split()[0] != digest:
            raise SystemExit(f'Copy checksum mismatch: {destination}')
        modified = now - index * 2
        timestamp = datetime.fromtimestamp(modified, timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        shell('touch', '-m', '-d', timestamp, destination)
        # Complete adb's pending write and populate dimensions before checking
        # recency. Pending MediaStore rows are invisible in the photo picker.
        shell('content', 'call', '--uri', 'content://media',
              '--method', 'scan_file', '--arg', media_path)
        for _ in range(20):
            row = query(media_path)
            if (re.search(r'_id=\d+', row) and 'is_pending=0' in row
                    and f'date_modified={modified}' in row):
                break
            time.sleep(.5)
        else:
            raise SystemExit(f'MediaStore did not finish indexing {destination}: {row}')
        taken = re.search(r'datetaken=([^,]+)', row).group(1)
        # The dataset photos have no EXIF capture date. Android then sorts by
        # file modification time. Do not silently claim recency for another
        # photo whose old embedded date could override the refreshed file date.
        if taken != 'NULL' and abs(int(taken) // 1000 - modified) > 60:
            raise SystemExit(f'Embedded capture date overrides recency for {destination}: {row}')
        print(f'{index + 1}: {destination} (verified copy; recent gallery date)')
    print('Open the photo picker → Photos → newest row. Copies remain in Pictures/NoteVisionQA.')


if __name__ == '__main__':
    main()
