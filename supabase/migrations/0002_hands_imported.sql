-- Switch the free trial from "3 hours of wall-clock usage" to "100
-- imported hands". This adds a new counter column to public.user_usage
-- and a new SECURITY DEFINER RPC that the Swift client calls after every
-- successful import.
--
-- The legacy `total_trial_seconds` column and `add_usage_seconds` RPC
-- from 0001 are intentionally LEFT IN PLACE so a rollback just needs a
-- client-side revert — no destructive DDL. Once the client change is
-- confirmed stable they can be dropped in a follow-up migration.

-- ---------------------------------------------------------------------------
-- Column
-- ---------------------------------------------------------------------------
alter table public.user_usage
    add column if not exists hands_imported integer not null default 0;

-- ---------------------------------------------------------------------------
-- RPC: atomic increment
--
-- Same shape as add_usage_seconds — takes a non-negative delta, returns
-- the full user_usage row. Upserts the row so a brand-new user's first
-- import creates the counter and increments it in one round-trip.
-- ---------------------------------------------------------------------------
create or replace function public.add_imported_hands(delta integer)
returns public.user_usage
language plpgsql
security definer
set search_path = public
as $$
declare
    uid uuid := auth.uid();
    row public.user_usage;
begin
    if uid is null then
        raise exception 'not authenticated';
    end if;
    if delta < 0 then
        raise exception 'delta must be non-negative';
    end if;

    insert into public.user_usage (user_id, hands_imported)
    values (uid, delta)
    on conflict (user_id) do update
        set hands_imported = public.user_usage.hands_imported + excluded.hands_imported,
            updated_at = now()
    returning * into row;

    return row;
end;
$$;

revoke all on function public.add_imported_hands(integer) from public;
grant execute on function public.add_imported_hands(integer) to authenticated;
