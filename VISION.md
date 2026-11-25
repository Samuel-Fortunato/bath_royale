# Bath Royale vision

Bath Royale helps people find and rate bathrooms while making exploration a little ridiculous. It should be genuinely useful, community-driven and welcoming without taking itself too seriously. The first community is the University of Aveiro; the product and data model should leave room for other universities, cities and countries.

## Experience

- Discover bathrooms and read useful community reviews, including the existing humorous rating descriptions.
- Keep a personal collection and record visits, like a toilet Pokédex. Every review describes one real visit; reviewing is optional and an unreviewed visit is complete.
- Compare bathrooms through overall and category-specific rankings.
- Explore with maps and location-aware discovery when those features are ready.
- Celebrate exploration with achievements, XP, levels, statistics, leaderboards, friends and challenges.

## Principles

- **Useful first:** make relevant, understandable information easy to find.
- **Playful, not hostile:** retain the existing visual personality and humor while respecting users and communities.
- **Local before community:** complete a functional local prototype before adding shared infrastructure.
- **Privacy and trust:** consider safety, consent, moderation and privacy, especially for location and bathroom photos, before enabling community features.
- **Grow thoughtfully:** start at Aveiro without hard-coding the product to a single campus; favor maintainable solutions and avoid premature complexity.
- **Accessible and inclusive:** make the experience usable across screen sizes and for a broad range of people.

## Decisions still open

The local prototype links each review to one visit and keeps reviews optional, as described in [the data model](docs/data-model.md). Multiplayer review and visit policies, ranking formulas, community migration strategy, location hierarchy, photo safeguards, moderation policy and gamification rules remain to be designed. Supabase and PostgreSQL are preferred candidates for the community backend, subject to evaluation before implementation. Specific features and rules in this vision are direction, not a finalized specification.

## Catalogue and contribution direction

The future catalogue should combine curated official bathrooms, public community contributions subject to validation and moderation, and private custom bathrooms for personal collections. Personal custom tags should remain personal unless explicitly proposed and accepted into the shared catalogue.

Gamification and reputation-based progression may unlock privileges to propose public bathrooms and community tags, and eventually help validate contributions. Privileges must work alongside moderation, duplicate prevention, contribution quality and appropriate submission limits. Recording private experiences must never require earning privileges. Exact progression rules, permission levels and moderation workflows remain undecided. Phase 1 retains unrestricted local experimentation; these visibility and permission models are not implemented.
