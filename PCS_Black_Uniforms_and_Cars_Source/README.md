# Black Uniforms and Police Cars — v1.1.0

Author: Joe "Gambit" Bradford

Black uniform shirts and matching black pants for all 12 supplied male and female
officer variants. The player/Chief wears a white shirt and black pants, with matching
white first-person sleeves. Police cars have black bodywork with white Winston Springs
Police lettering. The normal and damaged car textures are included.

Badges, patches, hats, equipment, and vehicle mechanics retain their existing
appearance or behavior. This is a texture replacement mod. UE4SS is not required.

## Install or update

1. Close Police Chief Simulator.
2. Extract the entire player ZIP.
3. Double-click `Install_Black_Uniforms_and_Cars.bat`.

The installer finds the Steam installation automatically. If it cannot find a
unique installation, choose the game's executable in the file window. Existing
versions of these nine texture files are backed up before replacement. Other
mods and UE4SS are preserved. No mods.txt edits or hotkeys are needed.

If Windows denies access to the game folder, right-click the batch file and
choose **Run as administrator**. The installer prints its log location if it fails.

For manual installation, copy the nine files inside `Payload/~mods` into:

`Police Chief Simulator/PoliceChiefSimulator/Content/Paks/~mods`

Create `~mods` if it does not exist. Replace the older files with these same names.
Do not keep renamed copies of the old containers elsewhere in `Paks`.

## Remove

Close the game and remove only these files from `Content/Paks/~mods`:

- `zz_PCS_Black_Uniforms_P.pak`
- `zz_PCS_Black_Uniforms_P.utoc`
- `zz_PCS_Black_Uniforms_P.ucas`
- `zz_PCS_Black_PoliceCar_P.pak`
- `zz_PCS_Black_PoliceCar_P.utoc`
- `zz_PCS_Black_PoliceCar_P.ucas`
- `zz_PCS_Chief_Uniform_P.pak`
- `zz_PCS_Chief_Uniform_P.utoc`
- `zz_PCS_Chief_Uniform_P.ucas`

To restore the previous version instead, copy its files back from your
download or the timestamped `PCS_Black_Uniforms_Backups` folder inside the
`PoliceChiefSimulator` project folder. A backup contains only files replaced
during that installation. Do not delete the whole `~mods` folder.

## Compatibility and validation

Other mods replacing the same officer diffuse textures or police-car body
textures can conflict. RoboCop's separate model and portrait containers are
not replaced by this installer. Game updates that change these texture assets
or their paths may require a mod update.

The author confirmed the black shirts and cars working in game. Black pants are verified across all 12 decoded officer textures. Version 1.1.0
adds the Chief outfit, verified in the first-person and full-body textures. Offline checks
cover protected badge/detail colors, streaming mip readability, bulk hashes,
package paths, installer upgrades, backups, and rollback. The added Chief outfit, pants, and this cosmetic installer have not been run
in the Windows game here.

## Source

The GitHub source ZIP contains the installer and texture-processing source,
build instructions, and validation records. It excludes the game's artwork and
external tool binaries. It is not the player installer download; the player ZIP
contains the required `Payload/~mods` files.

See `Source/README.md` and `GitHub_Update_Instructions.txt`.
