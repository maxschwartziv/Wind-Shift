"""Write GRIB test files with ecCodes for the game's GRIB reader (game/tests/grib_test.gd).

Every file holds a linear wind (or current) field, so bilinear interpolation reproduces it exactly
and the test can check values at any point. Variants cover GRIB1 and GRIB2, simple and complex
packing, both scanning directions, both longitude conventions, a land bitmap and an unsupported
packing.

Run: pipeline/.venv/Scripts/python pipeline/tools/make_test_gribs.py
"""

from pathlib import Path

import eccodes as ec
import numpy as np

OUT = Path(__file__).resolve().parents[2] / "game" / "tests" / "data"


def u_of(lat, lon, hour):
    return 5.0 + (lat - 33.0) + 0.5 * (lon + 118.0) + 0.1 * hour


def v_of(lat, lon, hour):
    return -3.0 + 0.3 * (lat - 33.0) - 0.2 * (lon + 118.0) + 0.05 * hour


def write(path, edition, packing, kind="wind", north_first=True, lon360=True, land=False):
    lats = np.arange(35.0, 31.75 - 1e-9, -0.25) if north_first else np.arange(31.75, 35.0 + 1e-9, 0.25)
    lons = np.arange(-119.5, -116.0 + 1e-9, 0.25)
    with open(path, "wb") as f:
        for hour in (0, 3):
            for comp in ("u", "v"):
                sample = "regular_ll_sfc_grib2" if edition == 2 else "regular_ll_sfc_grib1"
                h = ec.codes_grib_new_from_samples(sample)
                ec.codes_set(h, "dataDate", 20250425)
                ec.codes_set(h, "dataTime", 1200)
                ec.codes_set(h, "Ni", len(lons))
                ec.codes_set(h, "Nj", len(lats))
                ec.codes_set(h, "jScansPositively", 0 if north_first else 1)
                lo1, lo2 = lons[0], lons[-1]
                if lon360:
                    lo1, lo2 = lo1 % 360.0, lo2 % 360.0
                ec.codes_set(h, "latitudeOfFirstGridPointInDegrees", float(lats[0]))
                ec.codes_set(h, "latitudeOfLastGridPointInDegrees", float(lats[-1]))
                ec.codes_set(h, "longitudeOfFirstGridPointInDegrees", float(lo1))
                ec.codes_set(h, "longitudeOfLastGridPointInDegrees", float(lo2))
                ec.codes_set(h, "iDirectionIncrementInDegrees", 0.25)
                ec.codes_set(h, "jDirectionIncrementInDegrees", 0.25)
                if kind == "wind":
                    short = "10u" if comp == "u" else "10v"
                else:
                    short = "ucurr" if comp == "u" else "vcurr"
                if edition == 2 and kind == "current":
                    ec.codes_set(h, "discipline", 10)
                    ec.codes_set(h, "parameterCategory", 1)
                    ec.codes_set(h, "parameterNumber", 2 if comp == "u" else 3)
                    ec.codes_set(h, "typeOfFirstFixedSurface", 1)
                elif edition == 1 and kind == "current":
                    ec.codes_set(h, "table2Version", 2)
                    ec.codes_set(h, "indicatorOfParameter", 49 if comp == "u" else 50)
                    ec.codes_set(h, "indicatorOfTypeOfLevel", 1)
                else:
                    ec.codes_set(h, "shortName", short)
                ec.codes_set(h, "stepRange", str(hour))
                fn = u_of if comp == "u" else v_of
                grid = np.array([[fn(la, lo, hour) for lo in lons] for la in lats])
                ec.codes_set(h, "packingType", packing)
                ec.codes_set(h, "bitsPerValue", 16)
                if land:
                    grid[: len(lats) // 3, -4:] = 9999.0  # a block of land in the north-east corner
                    ec.codes_set(h, "missingValue", 9999.0)
                    ec.codes_set_values(h, grid.flatten())
                    ec.codes_set(h, "bitmapPresent", 1)
                ec.codes_set_values(h, grid.flatten())
                ec.codes_write(h, f)
                ec.codes_release(h)
    print(path.name, path.stat().st_size, "bytes")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    write(OUT / "g2_simple.grb2", 2, "grid_simple")
    write(OUT / "g2_complex.grb2", 2, "grid_complex")
    write(OUT / "g2_complex_sd.grb2", 2, "grid_complex_spatial_differencing")
    write(OUT / "g2_south_first_lon180.grb2", 2, "grid_simple", north_first=False, lon360=False)
    write(OUT / "g1_simple.grb", 1, "grid_simple")
    write(OUT / "g2_current_land.grb2", 2, "grid_complex_spatial_differencing", kind="current", land=True)
    write(OUT / "g1_current.grb", 1, "grid_simple", kind="current")
    write(OUT / "g2_jpeg.grb2", 2, "grid_jpeg")
