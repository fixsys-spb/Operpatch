# Accessibility

Check-RdpPatch is a small diagnostic utility. It does not currently
implement formal accessibility conformance.

## Known limitations

- The GUI uses WinForms default controls, which follow the system theme
  and font scaling settings, but do not implement a custom high-contrast
  mode beyond what Windows already provides.
- The console version relies on ANSI colour codes for the verdict;
  screen readers may not announce coloured segments meaningfully.

## Reporting accessibility barriers

If you encounter an accessibility issue, please open a GitHub issue:
https://github.com/fixsys-spb/Operpatch/issues

Describe your environment (Windows version, screen reader or magnification
tool, DPI settings) and what you expected to be able to do.