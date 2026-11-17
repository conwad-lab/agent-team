# Memory upkeep

The weekly **Memory** step (`CLOUD.md` [R9]). Only the Coordinator's routine reads this file, in the week's first run, after the retro. The project memory is the index `MEMORY.md`, which every thread loads, and its topic files. The goal: every thread starts from an index that is short, current and holds no task status. You judge what is worth keeping; this file gives the limits and the forms.

## Rules

1. **Read** the index, every topic file, the threads active in the last 7 days (`list_threads` with `since`, then `read_thread` on each) and the board. A memory folder or thread list you cannot read is `blind` in the digest line, never skipped: a silent skip looks like a clean memory.
2. **Back up first.** Copy `MEMORY.md` and every file you will change to `<project folder>/memory-backup/YYYY-MM-DD/` before any change. No backup, no change.
3. **Correct.** A fact that a newer thread, file or the board contradicts is corrected in its topic file. A fact no longer true gets the line `Stale since YYYY-MM-DD: <why>` and leaves the index four weeks after that date. Never delete a topic file.
4. **Merge.** Two topic files on one subject become one; the other keeps the single line `Merged into [[name]] YYYY-MM-DD` and leaves the index.
5. **Index.** One line per live topic file, `- [name](file.md): <hook>`, at most 200 characters, and no task status (queue, "next", dated progress, open cards). A status line that holds a lasting fact moves into a topic file first; pure status is dropped, because the board and `ORDER.md` hold it. A topic file without a line gets one. Pointer lines the project itself added (project files, imported memory) stay, one each, within the same limit. Keep the index under 4 kB; merge topic files rather than go over.
6. **Rules are proposals.** A rule seen in two threads, or written down as standing, never moves by a memory edit alone. It becomes `Minne: <rule> → <file> — <evidence links>` under **Förslag** in the repo it concerns, in the retro's `board:` PR (`CLOUD.md` [W2]); a project-wide rule, or one for a repo without `ORDER.md`, becomes one digest line with the proposed project-instruction or rulebook text. It stays in memory, in a topic file, until the human's yes moves it ([R5]). Evidence already linked from a `Minne:` row never counts again.
7. **Vault.** A fact that belongs in a vault the project instructions name goes there by branch and PR under that vault's rules (its check before push), at most one PR per run; the memory keeps a pointer. No vault named: a proposal as in 6.
8. **Digest.** One line in the weekly digest: `Minne: <n> changes, <n> proposals, backup <link>`, plus `blind: <what>` when 1 applied. No card for this step.

Topic files keep their frontmatter (`name`, `description`, `type`). Threads go on writing memory as before; this step only cleans up after them.
