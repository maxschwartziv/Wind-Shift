"""Spike: stream MarineCadastre daily AIS files and keep rows inside the Newport to Ensenada race area.

Usage: python fetch_ais.py OUT_CSV DATE [DATE ...]   (dates as YYYY-MM-DD)
"""
import csv
import io
import sys
import urllib.request

import zstandard

URL = "https://noaaocm.blob.core.windows.net/ais/csv2/csv{y}/ais-{d}.csv.zst"
# Newport Beach to Ensenada, with margin offshore and past the Mexican border.
LON_MIN, LON_MAX = -118.6, -116.4
LAT_MIN, LAT_MAX = 31.6, 33.8


def main(out_path, dates):
    with open(out_path, "w", newline="", encoding="utf-8") as out:
        writer = None
        for d in dates:
            kept = total = 0
            with urllib.request.urlopen(URL.format(y=d[:4], d=d)) as resp:
                text = io.TextIOWrapper(zstandard.ZstdDecompressor().stream_reader(resp), encoding="utf-8", errors="replace")
                reader = csv.reader(text)
                header = next(reader)
                if writer is None:
                    writer = csv.writer(out)
                    writer.writerow(header)
                ilon, ilat = header.index("longitude"), header.index("latitude")
                for row in reader:
                    total += 1
                    try:
                        lon, lat = float(row[ilon]), float(row[ilat])
                    except (ValueError, IndexError):
                        continue
                    if LON_MIN <= lon <= LON_MAX and LAT_MIN <= lat <= LAT_MAX:
                        writer.writerow(row)
                        kept += 1
            print(f"{d}: kept {kept} of {total} rows", flush=True)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
