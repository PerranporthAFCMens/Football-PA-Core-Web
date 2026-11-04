-- Monzo pot transfers: retries wait longer each time (1, 4, 9 ... minutes, capped at 6 hours) and give
-- up after 10 attempts (about 5 hours), so a short Monzo outage can't use up the retries when the
-- worker runs every minute. Replaces monzo_worker_finish only.
-- Rollback: re-run monzo_worker_finish from 20261104090000_monzo_pot_transfers.sql.
create or replace function public.monzo_worker_finish(p_transfer_id uuid, p_status text, p_ref text default null,
                                                      p_error text default null)
 returns void language plpgsql security definer set search_path to 'public'
as $function$
begin
  if p_status not in ('completed', 'failed', 'rejected', 'pending') then raise exception 'Invalid status'; end if;
  update public.monzo_pot_transfers
     set status = case when p_status = 'pending' and attempts >= 10 then 'failed' else p_status end,
         release_at = case when p_status = 'pending'
                           then now() + make_interval(mins => least(attempts * attempts, 360))
                           else release_at end,
         monzo_deposit_ref = coalesce(p_ref, monzo_deposit_ref),
         last_error = p_error,
         updated_at = now(),
         completed_at = case when p_status = 'completed' then now() else completed_at end
   where id = p_transfer_id and status = 'processing';
end;
$function$;
revoke all on function public.monzo_worker_finish(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.monzo_worker_finish(uuid, text, text, text) to service_role;
