# ADR 0001 — Evaluate Supabase with a tested exit gate

Date: 2026-11-25. Status: **accepted for the bounded Phase 2.1A PoC; production hosting remains conditional**.

The owner prioritizes practical results and low maintenance through AI-assisted development, with no mandatory recurring hosting subscription. Flutter, Provider, Material 3 and SQLite already provide a working offline prototype. Shared data needs server-enforced authorization and a practical path away from a managed free service.

The owner accepted Supabase/PostgreSQL for a bounded fictional-data PoC. Consider managed Supabase Free only after a real managed-to-self-hosted restore and successful same-password login prove the exit. SQL relationships, constraints and RLS fit the existing model; managed operation reduces initial administration. PocketBase is the simpler small-hardware fallback if Supabase operations are too heavy. Appwrite has credible auth, permissions and migration tooling but no compelling simplicity advantage for this model. These are assessment conclusions; supporting official sources and proposals are in [architecture](architecture.md) and [portability](portability.md).

Phase 2.0 added documentation, optional locked Nix tools and a disposable database-component smoke test. Phase 2.1A now adds the verified local Auth/API/schema/authorization environment described in [the PoC runbook](local-poc.md). It introduces no production authentication, synchronization, shared catalogue, remote deployment or UI changes. No hosted migration is verified. Session 4D's hosted Android CI succeeded; physical-phone acceptance remains pending.

Before production implementation, the owner still needs to decide:

- The maintenance obligations of an eventual production self-hosted exit and which already available machine/architecture to rehearse later. Candidate acceptance for the local PoC is complete.
- Production sign-in method and an affordable confirmation/recovery email route; OAuth and local guest mode remain options, with no paid domain required now.
- Whether private visit/favourite cloud backup is opt-in, what public author/date metadata appears on reviews, and account logout/device-data/erasure expectations.
- Publication and author-edit moderation rules, repeated-review policy, conflict UX, offline/tombstone retention and backup recovery objectives.

Bathroom classification remains exploratory. Publicly discoverable catalogue entries and private personal history remain distinct; private bathrooms are excluded. Preserve original contributor attribution when administrators approve entries. Recognition/rewards should follow approval, with mechanics deferred.

Next: Phase 2.1B must supply independent full-stack export/restore and unchanged-password login evidence; Phase 2.1C must rehearse the actual managed-Free exit. Local schema, Auth and two-user authorization are verified in Phase 2.1A. Obtain remaining product direction before production implementation. If the exit, cost or maintenance gates fail, keep local operation and reconsider PocketBase rather than silently accepting paid hosting. The proposed sequencing is in [ROADMAP.md](../../ROADMAP.md).
