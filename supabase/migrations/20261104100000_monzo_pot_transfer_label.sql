-- Monzo pot transfers: the note put on each pot transfer in the Monzo app,
-- e.g. "Subs: Dan Gilbert (Porthleven 2nd)". Read only, service role only.
-- Rollback: drop function public.monzo_worker_transfer_label(uuid).
create or replace function public.monzo_worker_transfer_label(p_transfer_id uuid)
 returns text language sql stable security definer set search_path to 'public'
as $function$
  select left('Subs: ' || coalesce(p.display_name, m.payer_name, 'payment')
              || coalesce(' (' || (select string_agg(f.opponent, ', ' order by f.kick_off)
                                     from public.fixtures f where f.id = any(m.applied_fixture_ids)) || ')', ''), 100)
    from public.monzo_pot_transfers t
    join public.monzo_payments m on m.id = t.monzo_payment_id
    left join public.players p on p.id = m.player_id
   where t.id = p_transfer_id;
$function$;
revoke all on function public.monzo_worker_transfer_label(uuid) from public, anon, authenticated;
grant execute on function public.monzo_worker_transfer_label(uuid) to service_role;
