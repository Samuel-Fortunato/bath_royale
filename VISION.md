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

Bath Royale is a community-oriented exploration and bathroom-sharing application. Private bathrooms are no longer part of the vision: all published catalogue entries are intended to be publicly discoverable. Personal visit history can remain private independently of catalogue visibility. User proposals require appropriate validation and moderation before publication.

Approved bathroom contributions should eventually earn rewards and recognition, potentially XP, achievements and contributor recognition. Reward approval, not proposal submission. Preserve attribution to the original contributor even when administrators later validate or promote an entry. Exact mechanics and values remain undecided; no moderation, authentication, permissions or rewards are implemented in the local prototype.

## Classification exploration — not a decision

The owner is considering presenting bathrooms inside versus outside the University of Aveiro rather than Official/Community as primary categories. This remains exploratory. Distinguish geographic or institutional membership, catalogue origin/contributor attribution, and validation/verification status; these need not be mutually exclusive categories. A user contributing a missing bathroom inside the university should still receive contribution credit. Keep future universities, campuses and cities in view without finalizing category names, classification rules or geographic hierarchy.
