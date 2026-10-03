# SignPath preparation files

These are **drafts for provider review**, not a connected signing service. The
checked-in production configuration is deliberately unapproved and incomplete.
No script in this directory submits a signing request, holds a key, approves a
request, installs software or accesses player data.

`payload-v1.xml` restricts signing to the seven exact owned PE paths from
`inventory-policy.v1.json`. Upload the publish directory with these paths at the
GitHub artifact ZIP root. Third-party files retain their bytes and signatures.
`uninstaller-v1.xml` requires the exact Inno-generated basename and coordinated
version. `setup-v1.xml` signs only the final Setup envelope; it does not sign
nested Inno payloads. All use required parameters and exact product metadata.
Foundation must accept the generated-uninstaller origin and chained
payload/manifest/uninstaller/Setup workflow before use. Changing signed payload
bytes requires a new coordinated numeric product version.

The [official syntax](https://docs.signpath.io/artifact-configuration/syntax) and
[metadata restrictions](https://docs.signpath.io/artifact-configuration/reference#file-metadata-restrictions)
describe these XML attributes. `schema-v1.pin.json` records the official XSD
retrieved on 2026-10-03. Schema validation establishes grammar, not admission or
provider-policy acceptance. Download that exact schema to an ignored `target`
directory for the optional grammar check; an altered schema requires review.

```powershell
pwsh -NoProfile -File scripts/windows/Test-SignPathConfiguration.ps1
# Optional: supply the previously downloaded, hash-verified provider XSD.
pwsh -NoProfile -File scripts/windows/Test-SignPathConfiguration.ps1 -SchemaPath target/path/to/artifact-configuration-v1.xsd
# Restore/build the real coordinated publish first; cargo must be on PATH.
pwsh -NoProfile -File packaging/windows/signpath/New-SignPathInventory.ps1
```

The generator creates a fresh ignored `target/winui/signpath-dossier/<id>` and
never overwrites one. It records exact publish file hashes, seven owned PE
targets, upstream PE/non-PE files, source/publish version agreement, NuGet lock
identities and original cached license files, and the Windows Runner non-dev
Cargo dependency closure with declared licenses. Microsoft package terms may
differ from source repository licenses. The generated data keeps uncertain
licenses and possible System Libraries exceptions open for provider review.
No automatic restore, schema download, signing, installation or cleanup occurs.

`SignPathConfiguration.ps1` validates declared production prerequisites and safe
request parameters. Its validation cannot prove external approval, roles, MFA,
token permissions, origin or certificate trust. Pass only a boolean indicating
token availability; never pass or print a token. Actual signing additionally
requires protected provider setup, GitHub-hosted origin, human approval and
post-sign Windows trust/RFC3161/DER-pin validation through `WindowsSigning.ps1`.

See the canonical [code-signing policy](https://yangyus8.top/SteamWrapper/project/design/code-signing/)
for human responsibilities and current admission status.
