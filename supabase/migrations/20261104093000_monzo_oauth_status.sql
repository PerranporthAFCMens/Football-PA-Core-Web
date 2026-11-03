-- Monzo pot transfers: lets the monzo-oauth status page list connections (it cannot read the table directly).
-- Read only, service role only. Rollback: drop function public.monzo_oauth_connections().
create or replace function public.monzo_oauth_connections()
 returns table (id uuid, monzo_account_id text, pot_id text, transfers_from timestamptz)
 language sql stable security definer set search_path to 'public'
as $function$
  select c.id, c.monzo_account_id, c.pot_id, c.transfers_from
    from public.monzo_connections c where c.active order by c.created_at;
$function$;
revoke all on function public.monzo_oauth_connections() from public, anon, authenticated;
grant execute on function public.monzo_oauth_connections() to service_role;
