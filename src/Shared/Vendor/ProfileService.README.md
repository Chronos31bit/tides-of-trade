# ProfileService

ProfileService isn't on Wally, so it must be vendored manually.

## How to install

1. Grab the latest `ProfileService.lua` from:
   https://github.com/MadStudioRoblox/ProfileService/blob/master/ProfileService.lua

2. Drop it next to this file as `ProfileService.lua` (replace this README's
   sibling, not this README itself):

   ```
   src/Shared/Vendor/ProfileService.lua   <- the file you download
   src/Shared/Vendor/ProfileService.README.md  <- this file
   ```

3. Rojo will sync it to `ReplicatedStorage.Shared.Vendor.ProfileService`.
   `PlayerDataService` already requires it via that path.

## Why vendored, not Wally?

ProfileService's author ships releases as a single `.lua` file in the GitHub
repo and hasn't published to Wally. Vendoring is the supported install path —
pinning the file content also means the data layer can't break under us
because of an unrelated dependency upgrade.

## Updating

Replace the `.lua` file with a newer release. Read the upstream changelog
before bumping — ProfileService takes backwards compatibility seriously, but
the GlobalUpdates API has shifted in the past.
