//
// Source of truth for which public-facing sorcery skills the demoing-sorcery-skills
// runbook covers. The pre-commit guard `check-skill-coverage.ts` reads this
// list and refuses commits when a skill under `plugins/sorcery/skills/` is
// neither covered nor explicitly skipped here.
//
// When you add a new public skill, you must either add a step for it in
// SKILL.md and list it here as `covered`, or list it as `skipped` with a
// reason a future reader will accept (e.g., the skill can't run in the demo
// environment).

export type DemoSkill =
  | { name: string; status: "covered" }
  | { name: string; status: "skipped"; reason: string };

export const SKILLS: DemoSkill[] = [
  { name: "capturing-test-fixtures",   status: "covered" },
  { name: "claiming-authorship",       status: "covered" },
  { name: "following-best-practices",  status: "covered" },
  { name: "guarding-commits",          status: "covered" },
  { name: "launching-claude",          status: "covered" },
  { name: "learning-new-tech",         status: "covered" },
  {
    name: "running-claude-in-a-vm",
    status: "skipped",
    reason:
      "The demo runs inside a Tart VM. Apple's Virtualization framework " +
      "does not support nested virtualization, so Tart-in-Tart cannot boot. " +
      "Demo this skill from the host instead.",
  },
  { name: "running-improvement-loops", status: "covered" },
  { name: "summarizing-sessions",      status: "covered" },
  { name: "using-dot-claude",          status: "covered" },
  { name: "using-llm-tasks",           status: "covered" },
  {
    name: "writing-commit-messages",
    status: "skipped",
    reason:
      "Exercised implicitly on every commit step throughout the runbook " +
      "via the commit-msg hook the skill installs; no standalone walkthrough " +
      "step adds value.",
  },
];
