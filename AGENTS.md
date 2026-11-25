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

- Automatically commit logical, verified units of work and push the completed, successfully verified task to the existing upstream branch. Routine local commits and pushes do not require owner approval. Use clear, concise Conventional Commit messages and separate unrelated changes.
- Stage only files relevant to each commit. Do not commit generated build artifacts or temporary files.
- Fetch and check the upstream before pushing. If the remote branch has diverged, report the situation; do not automatically merge, rebase or perform potentially destructive operations.
- Never force-push, rewrite history, discard the owner's changes, publish secrets or push incomplete or failing work. Merging branches still requires explicit instruction.
- Report created commits, push status, the CI URL and its current status concisely, then finish routine development tasks without waiting for GitHub Actions.
- Only wait for hosted CI when specifically implementing or debugging CI/CD, or when the owner explicitly requests it. Honor an explicit waiver of waiting, including for CI/CD work.
- Never claim unverified remote checks passed or infer remote compilation success from local checks.

## Changelog

- Maintain CHANGELOG.md with concise summaries of completed changes.

## NixOS environment and terminal output

- Discover executables through PATH and `command -v`; do not assume conventional filesystem locations.
- Use the existing Nix flake and direnv development environment. Codex is launched with `direnv exec . codex`; prefer direct commands when required tools are already on PATH and fall back to `direnv exec . <command>` when necessary. Avoid unnecessary shell wrappers and repeated environment initialization.
- Bubblewrap 0.12.0 is available on PATH; preserve normal sandboxing.
- If a utility such as Python is missing, use a temporary `nix shell` rather than installing it globally.
- Do not modify global NixOS or Home Manager configuration.
- Keep terminal summaries extremely concise.
