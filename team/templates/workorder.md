<!-- The brief a part's subagent gets (team/PARTS.md [P2]). The Builder fills in every line before starting any part and
     passes the text below as the Agent call's prompt; the subagent knows nothing else about the story. -->

You are building one part of a story. Another agent builds the rest at the same time and takes your part in only if a script finds it kept to this order.

## Goal
<one sentence>

## Files you may touch
<!-- Exactly the plan's list for this part, one path per line. A path ending in `/` allows that directory. -->
- `path/to/file`

Create, change or delete nothing else, in this repo or outside it.

## Interfaces to keep
<!-- Copied from the spine or the plan, never described: names, signatures, data shapes. -->
```
<signature or shape>
```

## Check
`<one command, run from the repo root>`: it must pass before you report.

## Do not
- touch a file not listed above, or a test's expectations to make it pass
- push, open a PR, or post anything on GitHub
- add or upgrade a dependency (installing what the lockfile already names is fine)
- start subagents
- make a design choice this order does not settle: stop and list it under Hinder

## Report
Commit your work in your worktree with the message `part <id>: <goal>` and leave nothing uncommitted. Then answer with what you wrote, the check command's output, and as the very last line exactly one of:

```
Hinder: inga
Hinder: <short list of what stopped you or what the order did not settle>
```
