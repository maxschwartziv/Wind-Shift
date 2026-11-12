"""AIS stage: stream MarineCadastre daily AIS files and keep rows inside the leg's area.

Reads leg["fleet"]["ais_dates"] (YYYY-MM-DD, UTC days) and writes the leg's ais_area_csv, skipping the
download if that file already exists. The area is the leg bounds plus 0.1 degree.
"""
import csv
import io
import urllib.request

import zstandard

URL = "https://noaaocm.blob.core.windows.net/ais/csv2/csv{y}/ais-{d}.csv.zst"


def build(leg, root, out):
    path = root / leg["fleet"]["ais_area_csv"]
    if path.exists():
        print(f"ais: {path.name} already present")
        return
    b = leg["bounds"]
    lon_min, lon_max = b["lon_min"] - 0.1, b["lon_max"] + 0.1
    lat_min, lat_max = b["lat_min"] - 0.1, b["lat_max"] + 0.1
    tmp = path.with_suffix(".partial")
    with open(tmp, "w", newline="", encoding="utf-8") as f:
        writer = None
        for d in leg["fleet"]["ais_dates"]:
            kept = total = 0
            with urllib.request.urlopen(URL.format(y=d[:4], d=d), timeout=600) as resp:
                text = io.TextIOWrapper(zstandard.ZstdDecompressor().stream_reader(resp), encoding="utf-8", errors="replace")
                reader = csv.reader(text)
                header = next(reader)
                if writer is None:
                    writer = csv.writer(f)
                    writer.writerow(header)
                ilon, ilat = header.index("longitude"), header.index("latitude")
                for row in reader:
                    total += 1
                    try:
                        lon, lat = float(row[ilon]), float(row[ilat])
                    except (ValueError, IndexError):
                        continue
                    if lon_min <= lon <= lon_max and lat_min <= lat <= lat_max:
                        writer.writerow(row)
                        kept += 1
            print(f"ais: {d}: kept {kept} of {total} rows", flush=True)
    tmp.replace(path)
