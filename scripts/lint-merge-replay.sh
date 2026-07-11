#!/usr/bin/env bash
#
# lint-merge-replay.sh — the two-argument replay gate (Spec.MergeEvidence).
#
# A decision word replays a board only as a pure function of (schedule, word)
# (`lawWordReplaysBoardUnderSchedule`); the schedule derives from the telemetry
# sealed in the SAME .s4cr record (`lawRecordedWordReplaysWithTelemetry`). A
# schedule-less `playAll(` reader outside the allowlist silently replays the
# WRONG board for any evidence-scaled capture — the migration hazard this lint
# exists to kill (the writer and every reader must move in the SAME commit).
#
# DETECTION IS CALL-SPAN AWARE, not line-based: for each `playAll(` the check
# joins the call line with its next two lines (house-style wrapped arguments),
# strips // comments first, and requires `schedule:` to appear AFTER the call
# token inside that window — so a correct two-argument call wrapped across
# lines passes, a `schedule:` in a trailing comment or in an enclosing
# function SIGNATURE on the same line does NOT excuse a one-argument body,
# and a genuine `playAll(word)` fails wherever it hides.
#
# ALLOWLIST (each entry justified):
#   SixFour/Merge/MergeBoard.swift      — DEFINES the forward (playAll ≡
#                                         playAll(schedule: derivedSchedule)).
#   SixFour/Merge/MergeEvidence.swift   — the schedule-derivation twin.
#   SixFourTests/MergeBoardTests.swift  — the golden gate PINNING the derived
#                                         special case (lawDerivedScheduleIsStep).
#   SixFourTests/MergeEvidenceTests.swift — pins constant-vs-scaled divergence.
#   SixFourTests/TimeSlideMathTests.swift — pins the slide's derived-game no-op
#                                         (lawSlideNeverWritesTheWord).
#
# Exit 0 = clean; exit 1 = drift. Run from the repo root.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

allow='SixFour/Merge/MergeBoard.swift|SixFour/Merge/MergeEvidence.swift|SixFourTests/MergeBoardTests.swift|SixFourTests/MergeEvidenceTests.swift|SixFourTests/TimeSlideMathTests.swift'

hits=$(find SixFour SixFourTests -name '*.swift' 2>/dev/null | sort | while read -r f; do
  if printf '%s' "|$allow|" | grep -qF "|$f|"; then continue; fi
  awk -v file="$f" '
    { sub(/\/\/.*$/, ""); lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        line = lines[i]
        # every playAll( occurrence on this (comment-stripped) line
        rest = line
        base = 0
        while ((p = index(rest, "playAll(")) > 0) {
          # the call window: from the token to the end of the line + 2
          # continuation lines (house-style wrapped arguments)
          window = substr(rest, p)
          if (i + 1 <= NR) window = window " " lines[i + 1]
          if (i + 2 <= NR) window = window " " lines[i + 2]
          if (index(window, "schedule:") == 0)
            printf "%s:%d: %s\n", file, i, line
          rest = substr(rest, p + 8)
          base += p + 7
        }
      }
    }' "$f"
done)

if [ -n "$hits" ]; then
  echo "MERGE-REPLAY lint: FAIL — schedule-less playAll( outside the allowlist"
  echo "(replay is (schedule, word); use S4MergeBoard.playAll(_:schedule:) with"
  echo " S4MergeEvidence.schedule(from:) on the record's own telemetry):"
  printf '%s\n' "$hits" | sed 's/^/  /'
  exit 1
fi
echo "MERGE-REPLAY lint: PASS — every replay reader is two-argument (schedule, word) or an allowlisted golden gate."
exit 0
