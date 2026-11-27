-- Generated validator replacement restores the explicit check-constraint grant.
-- This does not expose any data; the schema remains inaccessible to anonymous users.
grant execute on function app_private.grapheme_length(text) to authenticated;
