# SDD Development Project

This project uses SDD (Spec-Driven Development) with an external orchestrator (`sdd-loop.sh`).
The orchestrator drives each development phase as a separate Claude session with a focused prompt.

## Project Structure

- `.sdd/specs/spec.md` — Product specification (requirements, user stories, success criteria)
- `.sdd/plans/plan.md` — Technical plan (architecture, tech choices, data models)
- `.sdd/tasks/tasks.md` — Task list in checkbox format (`- [ ]` / `- [x]`)
- `.sdd/sprints/sprint-NNN/` — Sprint artifacts:
  - `contract.md` — What will be implemented and success criteria
  - `contract-review.md` — Independent review of the contract
  - `implementation.md` — Record of what was done
  - `evaluation.md` — Independent evaluation with scores
- `.sdd/shared-notes.md` — Cross-sprint learning and discovery notes
- `.sdd/reflections/` — Periodic reflection records
- `.sdd/state.json` — Current session state (phase, sprint, counters)
- `.sdd/config.json` — Configuration and limits

## Guidelines

- Read existing code before making changes
- Write tests for all new functionality
- Follow the existing code style and patterns
- Record discoveries and learnings in `.sdd/shared-notes.md`
- Be honest about difficulties and uncertainties in implementation records

## Git Version Control

Git commits are mandatory during implementation. The outer orchestrator tracks progress via commit history.
- Ensure `.gitignore` exists with sensible defaults before first commit
- Commit after each logical unit of work with clear messages (e.g., `feat(task-001): add user model`)
- After completing a sprint, commit `.sdd/` artifacts: `git add .sdd/ && git commit -m "chore(sdd): sprint NNN artifacts"`
- Zero commits in a sprint triggers deadlock detection in the outer loop
