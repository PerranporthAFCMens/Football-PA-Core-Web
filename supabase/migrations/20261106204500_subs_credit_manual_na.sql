-- Manager N/A: preserve cash already paid as player credit, rather
-- than silently discarding it when the existing status RPC deletes the row.
-- Other status changes retain their existing behaviour.
create or replace function public.set_subs_match_status_with_credit(
 p_team_id uuid,p_season_id uuid,p_fixture_id uuid,p_player_id uuid,p_status text
) returns jsonb language plpgsql security definer set search_path='public'
as $fn$
declare
 v_payment public.subs_payments%rowtype;
 v_result jsonb;
begin
 if auth.uid() is null or not public.can_manage_subs(p_team_id) then
   raise exception 'Subs permission required';
 end if;
 if lower(trim(coalesce(p_status,'')))='na' then
   select * into v_payment from public.subs_payments
   where fixture_id=p_fixture_id and player_id=p_player_id for update;
 end if;
 v_result:=public.set_subs_match_status(p_team_id,p_season_id,p_fixture_id,p_player_id,p_status);
 if lower(trim(coalesce(p_status,'')))='na' and v_payment.id is not null then
   if v_payment.method is distinct from 'Credit' then
     insert into public.subs_credit_ledger
       (club_id,team_id,season_id,player_id,fixture_id,origin_payment_id,amount_pence,note)
     values(v_payment.club_id,v_payment.team_id,v_payment.season_id,v_payment.player_id,
       v_payment.fixture_id,v_payment.id,v_payment.amount_pence,
       'Credit: manager marked fixture N/A')
     on conflict(origin_payment_id) do nothing;
   end if;
   perform public.apply_subs_credit(p_team_id,p_player_id);
 end if;
 return v_result;
end;
$fn$;
revoke all on function public.set_subs_match_status_with_credit(uuid,uuid,uuid,uuid,text)
 from public,anon,authenticated;
grant execute on function public.set_subs_match_status_with_credit(uuid,uuid,uuid,uuid,text)
 to authenticated;