"""Generate operator-only SQL; defaults to a read-only dry run. Never connects."""

import argparse
import csv
import json
import re
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Permanent protocol: do not change the namespace, prefix or supplied keys.
PREFIX = "bath-royale:official-catalogue:v1:"
FIELDS = "name emoji accent_rgb accent institution locality origin community account_private hidden publication_status verification_status contributor_id approved_by approved_at".split()


def identity(key):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, PREFIX + key))


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def load(path):
    entries = []
    keys, names, ids = set(), set(), set()
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames != ["key", "name", "emoji", "color"]:
            raise ValueError("Expected key,name,emoji,color header")
        for row in reader:
            key, name, emoji, color = (row[x] for x in reader.fieldnames)
            if None in row or None in (key, name, emoji, color):
                raise ValueError("Malformed CSV row")
            if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", key):
                raise ValueError("Invalid permanent key")
            if (
                not name
                or name != name.strip()
                or len(name) > 100
                or any(ord(c) < 32 for c in name)
            ):
                raise ValueError("Invalid bathroom name")
            if not emoji or not re.fullmatch(r"#[0-9A-Fa-f]{6}", color):
                raise ValueError("Expected emoji and six-digit RGB")
            normalized = " ".join(name.lower().split())
            target = identity(key)
            if key in keys or normalized in names or target in ids:
                raise ValueError("Duplicate key, normalized name or UUID")
            keys.add(key)
            names.add(normalized)
            ids.add(target)
            entries.append(
                dict(
                    key=key,
                    id=target,
                    content=dict(
                        name=name,
                        emoji=emoji,
                        accent_rgb=int(color[1:], 16),
                        accent=0,
                        institution=None,
                        locality=None,
                        origin="curated",
                        community=True,
                        account_private=False,
                        hidden=False,
                        publication_status="approved",
                        verification_status="verified",
                        contributor_id=None,
                        approved_by=None,
                        approved_at=None,
                    ),
                )
            )
    if not entries:
        raise ValueError("Empty catalogue")
    return entries


def plan(entries, apply=False):
    # Use the same writer lock order as domain mutations. Dry run never calls
    # sync_revision or touches sequences/feeds, and rolls back its temporary data.
    payload = literal(json.dumps(entries, ensure_ascii=False))
    projection = (
        "jsonb_build_object("
        + ",".join(literal(field) + ",existing_row." + field for field in FIELDS)
        + ")"
    )
    result = f"""\\set ON_ERROR_STOP on
BEGIN;
SELECT singleton FROM app_private.sync_clock WHERE singleton FOR UPDATE;
LOCK TABLE public.bathrooms IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE app_private.official_catalogue IN SHARE ROW EXCLUSIVE MODE;
CREATE TEMP TABLE catalogue_input ON COMMIT DROP AS
SELECT key,id::uuid bathroom_id,content FROM jsonb_to_recordset({payload}::jsonb)
 AS x(key text,id text,content jsonb);
-- Visibility is an independent reviewed moderation state, preserved on reimport.
UPDATE catalogue_input i SET content=jsonb_set(i.content,'{{hidden}}',r.applied_content->'hidden')
FROM app_private.official_catalogue r WHERE r.key=i.key;
DO $validate$
DECLARE item record; baseline app_private.official_catalogue; existing_row public.bathrooms;
BEGIN
 FOR item IN SELECT * FROM catalogue_input LOOP
  IF NOT app_private.valid_tag_emoji(item.content->>'emoji')
    OR app_private.grapheme_length(item.content->>'name') NOT BETWEEN 1 AND 100 THEN
   RAISE EXCEPTION 'Invalid domain content for key %',item.key;
  END IF;
  SELECT * INTO baseline FROM app_private.official_catalogue WHERE key=item.key;
  IF FOUND AND baseline.bathroom_id<>item.bathroom_id THEN
   RAISE EXCEPTION 'Permanent identity mismatch for key %',item.key;
  END IF;
  IF EXISTS(SELECT 1 FROM app_private.official_catalogue WHERE bathroom_id=item.bathroom_id AND key<>item.key) THEN
   RAISE EXCEPTION 'Registry identity collision for key %',item.key;
  END IF;
  SELECT * INTO existing_row FROM public.bathrooms WHERE id=item.bathroom_id;
  IF FOUND THEN
   IF baseline.key IS NULL OR {projection} IS DISTINCT FROM baseline.applied_content THEN
    RAISE EXCEPTION 'Existing record conflicts with import baseline for key %',item.key;
   END IF;
  ELSIF baseline.key IS NOT NULL THEN
   RAISE EXCEPTION 'Missing registered bathroom for key %',item.key;
  END IF;
  IF EXISTS(SELECT 1 FROM public.bathrooms b WHERE b.id<>item.bathroom_id
    AND NOT b.account_private AND (b.community OR b.publication_status='approved')
    AND lower(regexp_replace(btrim(b.name),'[[:space:]]+',' ','g'))=
      lower(regexp_replace(btrim(item.content->>'name'),'[[:space:]]+',' ','g'))) THEN
   RAISE EXCEPTION 'Catalogue name collision for key %',item.key;
  END IF;
 END LOOP;
END; $validate$;
SELECT i.key,i.bathroom_id,CASE WHEN r.key IS NULL THEN 'create'
 WHEN r.applied_content=i.content THEN 'unchanged' ELSE 'correct' END action
FROM catalogue_input i LEFT JOIN app_private.official_catalogue r USING(key) ORDER BY i.key;
"""
    if apply:
        result += """DO $apply$
DECLARE item record; previous jsonb;
BEGIN
 FOR item IN SELECT * FROM catalogue_input ORDER BY key LOOP
  SELECT applied_content INTO previous FROM app_private.official_catalogue WHERE key=item.key;
  IF NOT FOUND THEN
   INSERT INTO public.bathrooms(id,name,emoji,accent_rgb,accent,origin,community,
     account_private,hidden,publication_status,verification_status,contributor_id)
   VALUES(item.bathroom_id,item.content->>'name',item.content->>'emoji',
     (item.content->>'accent_rgb')::integer,0,'curated',true,false,false,'approved','verified',null);
   INSERT INTO app_private.official_catalogue VALUES(item.key,item.bathroom_id,item.content);
  ELSIF previous IS DISTINCT FROM item.content THEN
   UPDATE public.bathrooms SET name=item.content->>'name',emoji=item.content->>'emoji',
     accent_rgb=(item.content->>'accent_rgb')::integer WHERE id=item.bathroom_id;
   UPDATE app_private.official_catalogue SET applied_content=item.content WHERE key=item.key;
  END IF;
 END LOOP;
END; $apply$;
COMMIT;
"""
    else:
        result += "ROLLBACK;\n"
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalogue", type=Path, default=ROOT / "content/official_bathrooms.csv")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--apply", action="store_true", help="Emit committing SQL; operator executes after review"
    )
    args = parser.parse_args()
    content = plan(load(args.catalogue), apply=args.apply)
    with args.output.open("x", encoding="utf-8") as stream:
        stream.write(content)
    print("SQL written (" + ("APPLY" if args.apply else "DRY RUN") + "); no database accessed.")
