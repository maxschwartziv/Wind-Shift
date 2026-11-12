# Starter polars come from OpenCPN's polar files, with stand-ins

The starter boats use published polars from the OpenCPN Weather Routing plugin (GPL-3.0), shipped as separate data files with the license text, instead of polars generated from a speed model. ORC certificates were rejected because ORC's terms forbid redistribution. An open velocity prediction program was rejected in favor of published numbers. Boats with no published polar use a similar boat's polar and name it ("Alberg 30 (Alberg 35 polar)").

## Consequences

- The OpenCPN repository does not record the data's origin, and some files look like ORC certificate copies. If that origin is confirmed, the files must be replaced.
- Three of the five starters (Alberg 30, Catalina 400, Catalina 35) sail on another boat's polar.
