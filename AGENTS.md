# Development instructions

## Collaboration and scope

- Work autonomously on routine implementation decisions. Ask the project owner about significant product, architectural or design decisions. Treat unconfirmed requirements as proposals, not finalized decisions.
- Prefer simple, maintainable solutions and avoid unnecessary abstractions and dependencies.
- Preserve Flutter, Dart, Provider and Material 3 unless there is a compelling reason to change. Do not introduce a backend during Phase 1; evaluate the backend before implementing Phase 2.
- Keep the application functional throughout development. Preserve its humorous visual and written identity, including existing rating descriptions. Use Portuguese from Portugal for user-facing text and English for source code and technical documentation.
- Keep project dependencies reproducible through the existing Nix development environment. Do not modify the owner's global NixOS or Home Manager configuration. Never commit credentials, tokens or secrets.
- Update relevant documentation and roadmap milestones as work progresses; mark milestones complete only when verified.

## Implementation and verification

- Inspect the existing code and Git status before changing files; preserve the owner's changes. Keep changes focused and consistent with the project.
- Run formatting, static analysis, relevant tests and appropriate builds before considering implementation tasks complete. Record failures or checks that could not be run, and never claim a test or build passed unless it was actually executed successfully.
- Add meaningful automated tests for behavior as the prototype evolves. Keep bathroom entities and individual reviews distinct as that model is implemented.

## Git workflow

- Automatically create local commits after logical, verified units of work; do not ask for approval for routine local commits. Use clear, concise Conventional Commit messages and separate unrelated changes.
- Stage only files relevant to each commit. Do not commit generated build artifacts or temporary files.
- Do not push to GitHub or merge into main without explicit instruction. Never force-push, rewrite history or discard the owner's changes without explicit approval.
- Report commits created at the end of each task.
