# Iuppiter Verification Tools

Run these scripts from the repository root.

- `python3 tools/verify_catalog_resources.py`
  Checks that Swift catalog resource references resolve and that bundled non-doc resources are referenced.

- `python3 tools/verify_horizons_positions.py`
  Compiles the simulation model, compares catalog positions with JPL Horizons, and prints the worst angular/distance errors. This script uses only Python standard-library modules, Swift, and network access to the Horizons API.
