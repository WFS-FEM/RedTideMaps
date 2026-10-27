A summary and decision record of #5 and its sub-issues (#6, #8, #11, #10, with the hull method of #3), written for review by Dave and Yao before the #5 call, plus the clean-up that makes the trail easy to follow. It does not close #5: the decision (switch the nearshore rule on for both sensors and regenerate the maps, or keep the satellite-only maps) is still pending.

## What this PR carries

- `docs/issue5_nearshore-hybrid-summary/README.md`: the question, what each sub-issue found, the method change in plain terms, what changes in the maps, the decisions with dates and sources, what is pending, and a technical appendix (the rule as implemented, code and configuration, the verification chain, the numbers, the evidence files, a timeline). Every number traces to a table in an issue folder; nothing was computed afresh.
- `docs/README.md`: an index of the issue folders, in the order of the story, with the conventions they follow; one sentence in the root README points to both.
- Stale lines refreshed after the #10 move of the hybrid functions and the audit: `docs/issue5_nearshore-hybrid-summary/subissues/issue11_nearshore-hybrid-pipeline/README.md`, `data/coastline/README.md`, `docs/issue5_nearshore-hybrid-summary/subissues/issue8_nearshore-hybrid/issue8-nearshore-plan.md`, `docs/issue5_nearshore-hybrid-summary/subissues/issue6_VIIRS-zeros/README.md` (line-number citations dropped), `docs/review/science-review.md` (path of the #3 plan), `docs/review/draft-repo-audit-log.md` (a dated status note), `docs/issue5_nearshore-hybrid-summary/subissues/issue8_nearshore-hybrid/README.md` (which cell centres the two distance figures refer to).

Housekeeping done outside the PR: the merged branches `8-explore-nearshore` and `11-nearshore-hybrid-pipeline` deleted on GitHub (Holden) and locally; the empty untracked `docs/issue5_nearshore-hybrid-summary/subissues/issue8_explore-nearshore/` folder removed.

## Checkpoint

- [ ] Holden reviews the summary document; on approval a short comment on #5 links to it and the PR is merged.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
