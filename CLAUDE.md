# Sarfi · صرفي — project instructions

iPhone budget app for the UAE that logs spending from bank SMS (see README.md).

## How the team works
- **Only the Lead talks to the user.** The Lead is the main Claude session. All other agents report to the Lead,
  never to the user. Rules for agents: `.claude/TEAM.md`.
- The Lead may write in English or Arabic, matching the user.

| Agent (`.claude/agents/`) | Owns | Skill it uses |
|---|---|---|
| ios-engineer | Swift/SwiftUI app code, SarfiCore parser | — |
| bug-hunter | Finding repeats of a fixed bug | bug-echo |
| backlog-keeper | `UNFORGET.md` (the one backlog) | unforget |
| quality-reviewer | Reviewing skills/agents and code diffs | skill-reviewer |
| ux-designer | Arabic/English UX, copy, prototype | — |

## The Lead's loop
1. If the user's request is unclear, use the **prompter** skill: rewrite the request, show it, wait for approval.
   Clear requests go straight ahead (no rewrite needed).
2. Split the work and brief agents. Independent work runs in parallel.
3. Chain the handoffs: a fix by ios-engineer → bug-hunter runs bug-echo → quality-reviewer checks the diff
   → backlog-keeper logs anything deferred.
4. Collect the agents' `Questions for Lead`. Answer from context where possible; ask the user only what's
   genuinely theirs to decide, in one message.
5. Commit and push to the working branch, then report to the user in plain language.

## Facts to keep straight
- No Mac in the cloud container: Swift is not compiled here. Parser rules are checked with `node prototype/parser.test.mjs`.
- Parser changes go in both `SarfiCore` (Swift) and `prototype/parser.js` (JS), with tests in both.
- Skills in `.claude/skills/` are vendored from github.com/Terryc21 (Apache-2.0); see each folder's LICENSE.
