# Development setup and verification

The app uses the private database of `iCloud.mattgreat.house.Bible-Reading-Plan` for imported content. Progress uses `readingPlanState.v2` in the existing app KVS store. The widget uses the same App Group and KVS entitlement; it performs no CloudKit operations. Widget progress changes remain queued on disk until the app runs.

## Configure development

1. Open the project in Xcode, select the app target and team `MVM4SNA9YU`, and enable iCloud / CloudKit. Create or select the container `iCloud.mattgreat.house.Bible-Reading-Plan`. Regenerate the development provisioning profile with this entitlement. Keep the app and widget App Group `group.bible.reading.plan.tracker` enabled.
2. Configure a CloudKit management token in your local keychain using `xcrun cktool save-token` (see `--help`). Do not put a token in this repository or command history.
3. Import the schema into **development** from the repository root:

   ```sh
   xcrun cktool import-schema \
     --team-id MVM4SNA9YU \
     --container-id iCloud.mattgreat.house.Bible-Reading-Plan \
     --environment development \
     --validate --file CloudKit/Schema.ckdb
   ```

   If the container already has other record types, export its schema first and merge this record definition into it before importing. Do not reset the container. The `___recordID` queryable index is required for the paginated all-records query.
4. Run development-signed builds on two devices signed into the same iCloud account. Simulator tests deliberately isolate preferences/files and never contact real iCloud.

The schema language follows [Apple's cktool documentation and example](https://developer.apple.com/videos/play/wwdc2021/10118/). Private database records are per user; the app does not use the public database.

## Two-device acceptance check

- On device A, import a single plan and an array. Select one, change its day, and activate device B. Verify content, selection order, and progress match.
- Import identical content with a different integer ID on B: no duplicate. Import different content with the same integer ID: it remains separate.
- Disconnect B; delete an imported plan on A. Reconnect and activate B: the retained tombstone removes the plan and its selection/progress. Other plans from the array remain.
- While offline, import/change/delete on B; changes stay visible locally and the pending count remains nonzero. Reconnect and activate: pending work clears only after accepted uploads.
- Deliberately reimport deleted content: the newer revision restores it on both devices.
- Background and reopen across midnight: advance once. Reopen after several missed days: still advance once. Repeat on the second device without a second advance after it receives the shared day marker.
- Add small and medium widgets, verify their readings, and verify the next-day timeline. Widget refresh timing is controlled by the OS; opening the app requests an updated timeline.
- Change YouVersion/Logos preferences on A: B's preferences stay unchanged.

“Last Update” means the last completed refresh/upload cycle. KVS `synchronize()` acknowledges that the system queued a value, not that another device has received it. iCloud delivery is eventually consistent; simultaneous offline whole-state progress edits retain the prior timestamp-based last-write-wins policy. Imported content uses independent per-plan revisions and tombstones.

## Migration and recovery

`ReadingPlanStoreV2/snapshot.json` in the App Group contains the atomic local cache and pending queue. `store.lock` protects every read/modify/write across processes. `LegacyBackup/` retains original defaults and copied imported files before migration. Original defaults and import files are also left intact. Migration source markers commit in the same snapshot as their imported records.

Unknown or ambiguous legacy IDs remain in `unresolvedSelectedIDs` / `unresolvedProgress`; they are not guessed or shared with another device. A widget can initialize the shared store before the app: the app subsequently migrates its own Documents imports. New unrelated imports cannot inherit unresolved progress. Corrupt imports are reported in Manage Plans and remain in their original paths and backups; fix and reimport them through the file picker.

Mixed old/new versions do not share the v2 imported-plan identities. Update both devices for the new sync behavior. To investigate a migration issue, preserve both the v2 directory and backups before modifying them.

## Release prerequisite

No production schema deployment or app release is part of this change. After the two-device development checks pass, review and deploy the schema to production in CloudKit Console before shipping a release, and verify a production-signed build separately. See [Apple's container management guidance](https://developer.apple.com/documentation/CloudKit/managing-icloud-containers-with-cloudkit-database-app).

Local verification cannot substitute for these checks: no CloudKit management token is configured on this machine, and real-device iCloud delivery has not been exercised.

## Local checks completed

- Debug and Release simulator builds of the app and widget passed with Xcode 27.
- 33 isolated unit tests and 4 UI tests passed on both iPhone 16 Pro and iPad Pro 13-inch (M4), running iOS 18.6. The final migration adjustments were followed by another successful unit-test run on both devices.
- Reviewed the reading screen and small, medium, and empty widget preview screenshots on both form factors. These preview tests render the same SwiftUI views as the widget; they do not verify Home Screen scheduling or real iCloud delivery.
- `git diff --check` passed. No production deployment or release was performed.
