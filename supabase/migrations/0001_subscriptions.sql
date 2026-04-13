-- Subscription + free-trial usage tracking for Poker HUD.
--
-- Two tables:
--   user_usage    - per-user cumulative seconds spent in the free trial
--   subscriptions - server-of-truth subscription state, written only by the
--                   verify-receipt and app-store-notifications edge functions
--                   using the service_role key (so clients cannot forge it).

-- ---------------------------------------------------------------------------
-- user_usage
-- ---------------------------------------------------------------------------
create table if not exists public.user_usage (
    user_id uuid primary key references auth.users(id) on delete cascade,
    total_trial_seconds integer not null default 0,
    trial_started_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.user_usage enable row level security;

drop policy if exists "users read own usage"   on public.user_usage;
drop policy if exists "users insert own usage" on public.user_usage;
drop policy if exists "users update own usage" on public.user_usage;

create policy "users read own usage"
    on public.user_usage
    for select
    using (auth.uid() = user_id);

create policy "users insert own usage"
    on public.user_usage
    for insert
    with check (auth.uid() = user_id);

create policy "users update own usage"
    on public.user_usage
    for update
    using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- subscriptions
-- ---------------------------------------------------------------------------
create table if not exists public.subscriptions (
    user_id uuid primary key references auth.users(id) on delete cascade,
    product_id text not null,
    plan text not null check (plan in ('monthly','yearly')),
    status text not null check (status in ('active','expired','in_grace','revoked')),
    original_transaction_id text not null unique,
    latest_transaction_id text not null,
    current_period_start timestamptz not null,
    current_period_end timestamptz not null,
    auto_renew boolean not null default true,
    environment text not null check (environment in ('sandbox','production')),
    updated_at timestamptz not null default now()
);

alter table public.subscriptions enable row level security;

-- Clients can only read their own subscription row. Writes are performed
-- exclusively by edge functions using the service_role key, which bypasses RLS.
drop policy if exists "users read own subscription" on public.subscriptions;

create policy "users read own subscription"
    on public.subscriptions
    for select
    using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Helper: atomically increment a user's trial usage. Used by the Swift client
-- instead of read-modify-write, so concurrent devices can't trample each other.
-- ---------------------------------------------------------------------------
create or replace function public.add_usage_seconds(delta integer)
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

    insert into public.user_usage (user_id, total_trial_seconds)
    values (uid, delta)
    on conflict (user_id) do update
        set total_trial_seconds = public.user_usage.total_trial_seconds + excluded.total_trial_seconds,
            updated_at = now()
    returning * into row;

    return row;
end;
$$;

revoke all on function public.add_usage_seconds(integer) from public;
grant execute on function public.add_usage_seconds(integer) to authenticated;
