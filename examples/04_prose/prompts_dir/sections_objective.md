---
description: Phase-2 doer objective — write each section, one per iteration, as its own file.
parameters:
  total: null
---
Following the approved outline.md, write the guide ONE section at a time. There
are <%= total %> sections. Each section goes in its OWN new file under sections/,
named sections/NN_slug.md (NN = 01, 02, …, matching the outline order).

Each iteration: read outline.md and list the sections/ directory, then write the
NEXT outline section that has no file yet. Write real, opinionated, concrete
prose — no placeholders. Read REVIEW.md for the reviewer's feedback on the last
section and fix it if asked. Do not touch outline.md. Use bare relative paths
(no ".robot_lab_to"). Call submit_result each iteration naming the section.
