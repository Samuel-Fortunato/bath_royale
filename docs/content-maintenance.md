# Owner-maintained alpha content

The owner supplies the genuine bathroom catalogue, standard review tags and suggested emoji sets separately. A5.1 does not invent or approve that final content.

- **Catalogue:** create verified genuine records through the entitled account after the managed deployment gate. Preserve stable IDs and existing visit/review associations. Empty catalogue is supported. Never promote `backend/seed_development.py` data; that seeder and its credentials belong only to the isolated development environment.
- **Review tags:** edit the single provisional pool `reviewTagSuggestions` in `lib/models/content_suggestions.dart`. Entries contain an emoji and Portuguese label. Existing community suggestions, search, selected/custom tags, bounds and per-draft randomization remain automatic. Changing suggestions must never rewrite tags on stored reviews.
- **Picker emoji:** edit `bathroomEmojiSuggestions` in the same file. These are suggestions only; the single-emoji input remains unrestricted. Do **not** reorder/change `Bathroom.emojis` in `lib/models/bathroom.dart`: it is the historical identity fallback used by old bathrooms. Picker suggestions are now independent so owner curation cannot change their appearance.

After a content edit, run formatting, analysis and relevant creation/review/identity tests. No backend reset, migration or account reprovisioning is required merely to change suggestions. Catalogue records and published reviews must always reflect genuine submissions.
