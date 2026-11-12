"""Depth stage: subset the NOAA NCEI Southern California Coastal Relief Model (3 arc-second) over the leg bounds.

Writes <out>/depth.bin: int16 little-endian, elevation in decimeters (positive up, so water is negative),
clamped to -3276.7 m, rows from north to south, columns from west to east.
The grid header goes to <out>/depth.json for the manifest stage.
"""
import json

import numpy as np
import xarray as xr

SOURCES = {
    "crm_vol6": ("https://www.ngdc.noaa.gov/thredds/dodsC/crm/crm_vol6.nc",
                 "Depth: NOAA NCEI U.S. Coastal Relief Model, Southern California (vol. 6), 3 arc-second"),
    "crm_vol7": ("https://www.ngdc.noaa.gov/thredds/dodsC/crm/crm_vol7.nc",
                 "Depth: NOAA NCEI U.S. Coastal Relief Model, Central Pacific (vol. 7), 3 arc-second"),
    "etopo2022_n45w090": ("https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/15s/15s_surface_elev_netcdf/ETOPO_2022_v1_15s_N45W090_surface.nc",
                          "Depth: NOAA NCEI ETOPO 2022, 15 arc-second, with Great Lakes bathymetry"),
    "etopo2022_n60w090": ("https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/15s/15s_surface_elev_netcdf/ETOPO_2022_v1_15s_N60W090_surface.nc",
                          "Depth: NOAA NCEI ETOPO 2022, 15 arc-second, with Great Lakes bathymetry"),
}


def _subset(url, b):
    ds = xr.open_dataset(url)
    var = "z" if "z" in ds else list(ds.data_vars)[0]
    ycoord = "y" if "y" in ds.coords else "lat"
    xcoord = "x" if "x" in ds.coords else "lon"
    da = ds[var].sel({ycoord: slice(b["lat_min"], b["lat_max"]), xcoord: slice(b["lon_min"], b["lon_max"])}).load()
    return da.rename({ycoord: "y", xcoord: "x"})


def build(leg, root, out):
    b = leg["bounds"]
    names = leg.get("depth_source", "crm_vol6").split("+")
    raw = root / "data" / (f"{leg['id']}_crm.nc" if leg["id"] == "n2e-2025" else f"{leg['id']}_depth.nc")
    if not raw.exists():
        parts = [_subset(SOURCES[n][0], b) for n in names]
        if len(parts) == 1:
            z = parts[0]
        else:
            # Sources on offset grids: put every part on the first part's spacing over the whole bounds,
            # then take each cell from the first source that has a value there.
            step = float(abs(parts[0].y[1] - parts[0].y[0]))
            ys = np.arange(b["lat_min"], b["lat_max"] + step / 2, step)
            xs = np.arange(b["lon_min"], b["lon_max"] + step / 2, step)
            z = None
            for part in parts:
                g = part.sortby("y").interp(y=ys, x=xs, method="nearest")
                z = g if z is None else z.fillna(g)
        z.to_netcdf(raw)
    z = xr.open_dataarray(raw).load()
    z = z.sortby("y", ascending=False)  # north to south
    elev = np.nan_to_num(z.values, nan=0.0)
    lake = leg.get("lake_level_m")
    if lake is not None:
        # ETOPO gives lakebed height above sea level; the game wants height above the water surface.
        elev = elev - lake
    dm = np.clip(elev * 10.0, -32767, 32767).astype("<i2")
    CREDIT = SOURCES[names[0]][1] if len(names) == 1 else "Depth: NOAA NCEI U.S. Coastal Relief Model, volumes " + " and ".join(n.split("_vol")[-1] for n in names) + ", 3 arc-second"
    dm.tofile(out / "depth.bin")
    lat, lon = z.y.values, z.x.values
    header = {"file": "depth.bin", "type": "int16_dm", "credit": CREDIT,
              "lat_north": float(lat[0]), "lon_west": float(lon[0]),
              "dlat": float(lat[0] - lat[1]), "dlon": float(lon[1] - lon[0]),
              "rows": int(dm.shape[0]), "cols": int(dm.shape[1])}
    (out / "depth.json").write_text(json.dumps(header, indent=1))
    water = (dm < 0).mean() * 100
    print(f"depth: {dm.shape[0]}x{dm.shape[1]} cells, {water:.0f}% water, deepest {dm.min() / 10:.0f} m, "
          f"{(out / 'depth.bin').stat().st_size / 1e6:.1f} MB")
