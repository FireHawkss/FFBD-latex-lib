# Visual review checklist

Final human sign-off and Overleaf testing belong to the user. All 20 automated catalogue cases passed (19 successful documents and one expected diagnostic). These are not human readiness ratings.

Open the linked PDFs and assess direction, grouping, spacing, crossings, text and continuations. Record your rating in `manifest.json` under `visual_review`. Dense cases flagged below especially need review.

| Fixture | PDF / diagnostic | Agent review |
| --- | --- | --- |
| basic-chain | [basic-chain.pdf](references/basic-chain.pdf) | pass: Primary row now starts with four blocks. Connected return to the finish; two readable notes. |
| complex-branches | [complex-branches.pdf](references/complex-branches.pdf) | pass: Two complete pages with matching Continuation 8.1 labels; branch conditions and notes remain readable. |
| structures-feedback | [structures-feedback.pdf](references/structures-feedback.pdf) | review: Both group boundaries, captions and routes are legible. The Valid label touches a group border; review spacing and the large note allowance. |
| custom-down | [custom-down.pdf](references/custom-down.pdf) | pass: Clear straight downward flow, readable condition, note to the right, transparent serif blocks. |
| drone-real-world | [drone-real-world.pdf](references/drone-real-world.pdf) | pass: Alternating rows and feedback remain readable; asymmetric branch spacing is visible. |
| chain-8 | [chain-8.pdf](references/chain-8.pdf) | pending: Rendered and checked automatically; agent visual review not completed before requested wrap-up. |
| branches-15-unequal | [branches-15-unequal.pdf](references/branches-15-unequal.pdf) | pass: Short arm rejoins after the long serpentine arm; routing can be followed, with some long detours. |
| branches-30-unequal | [branches-30-unequal.pdf](references/branches-30-unequal.pdf) | review: Dense vertical bands have tight bends and several long arm routes. Human branch-clarity review is required. |
| joins-feedback-42 | [joins-feedback-42.pdf](references/joins-feedback-42.pdf) | review: First page inspected: some unrelated routes appear to share a corridor near Step 7. Review all pages for ambiguous merging before release. |
| dense-text-conditions | [dense-text-conditions.pdf](references/dense-text-conditions.pdf) | pending: Rendered and checked automatically; agent visual review not completed before requested wrap-up. |
| group-across-wrap | [group-across-wrap.pdf](references/group-across-wrap.pdf) | pending: Rendered and checked automatically; agent visual review not completed before requested wrap-up. |
| columns-hard-conflict | [columns-hard-conflict.txt](references/columns-hard-conflict.txt) | pending: Rendered and checked automatically; agent visual review not completed before requested wrap-up. |
| columns-soft | [columns-soft.pdf](references/columns-soft.pdf) | pending: Rendered and checked automatically; agent visual review not completed before requested wrap-up. |
| rowbreak-hard-soft | [rowbreak-hard-soft.pdf](references/rowbreak-hard-soft.pdf) | pending: Rendered and checked automatically; agent visual review not completed before requested wrap-up. |
| annotations-eight | [annotations-eight.pdf](references/annotations-eight.pdf) | pending: Rendered and checked automatically; agent visual review not completed before requested wrap-up. |
| scale-explicit | [scale-explicit.pdf](references/scale-explicit.pdf) | pending: Rendered and checked automatically; agent visual review not completed before requested wrap-up. |
| large-64-single | [large-64-single.pdf](references/large-64-single.pdf) | pending: Rendered and checked automatically; agent visual review not completed before requested wrap-up. |
| large-64-multipage | [large-64-multipage.pdf](references/large-64-multipage.pdf) | pending: Rendered and checked automatically; agent visual review not completed before requested wrap-up. |
| irregular-gap-adversary | [irregular-gap-adversary.pdf](references/irregular-gap-adversary.pdf) | pending: Rendered and checked automatically; agent visual review not completed before requested wrap-up. |
| displaced-label-adversary | [displaced-label-adversary.pdf](references/displaced-label-adversary.pdf) | pending: Rendered and checked automatically; agent visual review not completed before requested wrap-up. |

Readiness proportions for <10, 10–30 and 30–50 blocks remain unmeasured until human ratings are supplied. A geometrically valid dense drawing can still have confusing shared corridors. The 64-block single-page case deliberately reports overflow and retains scale 1; its clipped PDF is not a publication-ready result. Use its multipage counterpart.
