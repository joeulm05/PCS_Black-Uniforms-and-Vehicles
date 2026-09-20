# Build source — Black Uniforms and Police Cars v1.1.0

Author: Joe "Gambit" Bradford

## Build textures

Use Python 3.12, GCC, Pillow, NumPy, SciPy, cityhash, retoc 0.1.5 and repak 0.2.3.
Obtain retoc and repak separately and put them on PATH or set RETOC and REPAK.
Use the author's original Workers.zip, PoliceCar.zip and Chief Player Dump.zip game exports; the exact
input asset hashes are recorded in build_report.json. Artwork is not included
in the source download.

Run from this Source folder on Linux:

```sh
python3 -m pip install Pillow numpy scipy cityhash
gcc -O2 -Wall -Wextra recolor_assets.c -lm -o recolor_assets
export PCS_ASSET_INPUT=/absolute/path/to/original/exports
python3 build_mod.py
python3 validate_mod.py
python3 build_chief.py
python3 validate_chief.py
```

Copy the nine files from the generated `package/~mods` folder into the release
root's `Payload/~mods` folder. Update `Installer/manifest.json` with each file's
filename, size in bytes, and lowercase SHA-256 after rebuilding. Keep its exact
nine-file list. The installer rejects incomplete or mismatched payloads.

## How recoloring works

The native processor reads BC1 virtual-texture tiles without changing their
layout. Large blue fabric components identify the shirt. Large dark-navy
components with centers in the right half of the atlas and extending into its
lower fifth identify the pants on these supplied atlases. Other navy components,
including hat islands, are excluded. Pants become neutral near-black while
retaining tonal differences. Gold-bearing base-level blocks are preserved.

Pixel changes propagate through mip levels and tile borders. The builder updates
bulk SHA-1 hashes and the virtual-texture fallback color. All other asset metadata
is preserved. These masks are specific to the supplied texture layouts and must
be reviewed if future game assets change.

Car recoloring uses the existing normalized lettering rectangles and bright-paint
selection. The release's car containers are byte-identical to the version the
author confirmed in game.

## Chief outfit

`build_chief.py` reads the reviewed Chief skeletal mesh's position, UV and index
buffers. It welds matching positions and identifies the connected shirt and pants
components, verifying their counts and spatial bounds. A SHA-256 guard rejects a
mesh different from the reviewed export. Triangles are rasterized into a clothing
mask; nearest triangle labels cover the texture padding. The base-color filter
then whitens navy shirt cloth and darkens navy trouser cloth. The first-person
shirt uses its separate texture. Face, skin, normals, material assignments, and
mesh data are not replaced. Gold-bearing blocks are protected.

`chief_build_report.json` records source hashes and
`chief_validation.json` records pixel/metadata/mip checks.

## Installer

`Install_Black_Uniforms_and_Cars.bat` launches Windows PowerShell.
`Installer/Discovery.ps1` locates Steam libraries and game installations.
`Installer/Core.ps1` verifies the nine-file payload, stages copies, backs up
replaced files, installs, verifies, and restores prior files on a failed write.
`Installer/Install.ps1` provides the user-facing entry point and logs.

Run the fixture checks with PowerShell from the release root after supplying the
player payload:

```powershell
pwsh -NoProfile -File Source/Tests/test_discovery.ps1
pwsh -NoProfile -File Source/Tests/test_installer.ps1
```

The fixtures do not launch or modify an installed game. Read validation.json and
Installer_Validation.json for actual check results and remaining platform limits.

## External tools

- https://github.com/trumank/retoc
- https://github.com/trumank/repak
- https://github.com/FabianFG/CUE4Parse

These are separate upstream projects. Game artwork remains subject to its
respective ownership; publishing this processing source does not license it.
