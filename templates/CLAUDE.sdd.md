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
- Make meaningful git commits with clear messages
- Record discoveries and learnings in `.sdd/shared-notes.md`
- Follow the existing code style and patterns
- Be honest about difficulties and uncertainties in implementation records
