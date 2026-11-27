-- A4: same expanded single-grapheme symbol ranges in the shared client/server validator.
create or replace function app_private.valid_tag_emoji(value text) returns boolean
language plpgsql immutable strict set search_path = '' as $$
declare first integer:=ascii(value); last integer:=ascii(right(value,1));
begin
 if app_private.grapheme_length(value)<>1 then return false; end if;
 if first in (8205,65039) or first between 127995 and 127999 then return false; end if;
 if first between 127462 and 127487 then
   return char_length(value)=2 and last between 127462 and 127487; end if;
 if first in (35,42) or first between 48 and 57 then return last=8419; end if;
 return first between 8596 and 8601 or first between 8617 and 8618
  or first between 9642 and 9643 or first in (9654,9664) or first between 9723 and 9726
  or first between 10548 and 10549 or first between 11013 and 11015 or first between 11035 and 11036
  or first between 126976 and 129791 or first between 9728 and 10175
  or first in (169,174,8252,8265,8482,8505,8986,8987,9000,9167,
  9193,9194,9195,9196,9197,9198,9199,9200,9201,9202,9203,9208,9209,9210,
  9410,11088,11093,12336,12349,12951,12953);
end;
$$;
