#!/bin/bash
# Look B concepts: one lumina call per line in parallel; re-save as real PNG.
cd "$(dirname "$0")"
STYLE="bright stylized hand-painted 3D game asset like a modern indie game, saturated colours, soft warm sunset lighting, single object only, 3/4 view from slightly above, compact composition small in frame with wide empty margin on all sides, plain flat light-grey studio background, no ground plane, no shadow, no other objects, no text, no letters, no logos, no symbols, solid chunky shapes with no thin parts"
while IFS=$'\t' read -r n d; do
  ( env -u PYTHONPATH lumina -p "$d. $STYLE" --aspect-ratio 1:1 --image-size 2K -o . -f ${n}_concept.png >/dev/null 2>&1
    sips -s format png ${n}_concept.png --out ${n}_concept.png >/dev/null 2>&1
    echo "$n $(file -b ${n}_concept.png 2>/dev/null | cut -c1-20)" ) &
done < prompts.tsv
wait
