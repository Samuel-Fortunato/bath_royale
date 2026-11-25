# Bath Royale vision

Bath Royale helps people find and rate bathrooms while making exploration a little ridiculous. It should be genuinely useful, community-driven and welcoming without taking itself too seriously. The first community is the University of Aveiro; the product and data model should leave room for other universities, cities and countries.

## Experience

- Discover bathrooms and read useful community reviews, including the existing humorous rating descriptions.
- Keep a personal collection and record visits, like a toilet Pokédex.
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

The local prototype defines minimal review ownership and explicit latest-visit semantics in [the data model](docs/data-model.md). Multiplayer review and visit policies, ranking formulas, persistence and migration strategy, location hierarchy, photo safeguards, moderation policy and gamification rules remain to be designed. Supabase and PostgreSQL are preferred candidates for the community backend, subject to evaluation before implementation. Specific features and rules in this vision are direction, not a finalized specification.
