# Updating third-party distribution notices

`NOTICE.md` and `manifest.v1.json` describe the exact legal material staged by
`scripts/windows/Stage-WinUIThirdPartyNotices.ps1`. Original upstream text lives
in the adjacent `third-party-licenses` directory. Legal originals are retained
in their original language and format, including the Microsoft SDK RTF.
Git text normalization is disabled for these originals, the hashed notice
entry point and its catalog; preserve their byte hashes when updating them.

The catalog covers the Windows Runner's non-dev dependency closure (including
build/proc-macro dependencies), redistributed NuGet/runtime components and the
generated Inno installer. It excludes standalone development SDK/compiler
tasks. Original .NET third-party notices and Microsoft package NOTICE files
are included separately from the respective license text. This records
distribution materials; Foundation admission and any System Libraries
exception remain separate review items.

When dependency versions change, review the actual locked package and original
upstream license/notice files. Copy only those legal files into this directory's
adjacent canonical collection, then update the component references, original
source, length and SHA-256 in the catalog and the reader-facing table. Do not
collect arbitrary cache directories. Do not translate or substitute legal
terms based only on the source repository's license badge.

Run the focused test with PowerShell 7 and cargo on PATH:

```powershell
pwsh -NoProfile -File scripts/windows/Test-WinUIThirdPartyNotices.ps1
pwsh -NoProfile -File scripts/windows/Stage-WinUIThirdPartyNotices.ps1 -PublishDirectory target/winui/publish -VerifyOnly
```

Staging is offline and restricted to fresh repository `target/winui` candidates.
It preserves matching existing files and rejects different bytes, missing
notices, unsafe paths, oversized files and dependency-version drift. It never
reads player data or copies arbitrary credentials. The final portable ZIP and
installer must both retain `THIRD_PARTY_NOTICES.md`, `LICENSES/index.json` and
every indexed legal file.
