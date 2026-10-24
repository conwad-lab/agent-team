---
name: distill-feedback
description: Turn the human's past feedback on this project into review principles for REVIEW.md, so the Judge reviews with the human's taste. Run when a project enters cloud mode, or after the human has corrected the team several times on the same kind of point.
---

# distill-feedback

The human is the bottleneck when every PR needs their eye because the reviewers do not know what they care about. This skill writes that down once, so the Judge can apply it.

## Steps

1. **Collect.** Read, for this repo: the human's PR comments and review comments (`gh api repos/{owner}/{repo}/pulls/comments`, `gh pr list --state all` + `gh pr view <n> --comments`), PRs closed without merge and the reason, rows in `.team/ORDER.md` that correct or reverse earlier work, decisions recorded in story Logs, and handoff or decision notes the human points you to. Keep the source (PR number, file, date) for every item.
2. **Condense.** Write the explicit principles: what the human repeatedly asks for or rejects, each as one sentence a reviewer can check, with two or more sources each. Drop one-offs.
3. **Implicit principles.** Write a second, short list: principles the decisions follow that the human never stated. Mark each `(inferred)` with the decisions it rests on.
4. **Propose.** Open a PR whose story line is `Rulebook story.` that adds both lists under `## The human's principles` in `REVIEW.md` (create the file if missing, and make sure Team settings' **Review checks** names it). The human approves the list; an inferred principle they reject is deleted, not reworded.

## Rules

- Quote the human only from their own words in the sources. Never invent a principle to round out the list.
- Ten principles that are used beat thirty that are not. Keep the list on one screen.
- Do not put client data or secrets from the sources into `REVIEW.md`.
