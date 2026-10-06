## Description

<!-- Briefly describe what this PR changes and why. -->

## Type of change

- [ ] Bug fix (non-breaking)
- [ ] New feature (non-breaking)
- [ ] Breaking change
- [ ] Documentation update
- [ ] CI / tooling

## Checklist

- [ ] `Invoke-ScriptAnalyzer -Path .\Check-RdpPatch.ps1` returns no warnings.
- [ ] `Invoke-ScriptAnalyzer -Path .\Check-RdpPatch-GUI.ps1` returns no warnings.
- [ ] `npx remark CHANGELOG.md CHANGELOG.ru.md README.md README.ru.md --frail` returns no warnings.
- [ ] Changelog updated under `[Unreleased]` in both `CHANGELOG.md` and `CHANGELOG.ru.md`.
- [ ] Tested on a real Windows machine (specify OS + build below).

## Tested on

- OS:
- Build / UBR:
- Form factor tested: `[ ] .ps1` `[ ] GUI` `[ ] EXE`