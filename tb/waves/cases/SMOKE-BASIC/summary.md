# SMOKE-BASIC

Directed bring-up waveform for the standalone `smoke_basic` testcase.

## Intent

- prove the standalone harness produces a clean request/reply cycle
- provide a minimal reference waveform for parser, bus-dispatch, and reply assembly debug
- anchor later promoted cases to a known-good baseline

## Notes

- source VCD path is an existing local artifact generated from the harness
- GTKWave save file is still a template; a fully curated case-specific `.gtkw` is not published yet
