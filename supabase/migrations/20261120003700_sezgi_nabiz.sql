-- SÜ-BG (Beat Greedy; ADIL_PUAN §6, kurucu onayı 16 Kasım 2026): Keşif ve Yarış'ta duraklatılabilir süre.
-- Ortak deseni (20261120003500 ortak.nabiz) Beat Greedy'nin kendi deneme tablosunda uygular:
-- 1) sezgi.attempts.aktif_ms, son_nabiz. sezgi.nabiz(deneme): açık ve günü bitmemiş denemede aktif_ms'e önceki nabızdan bu
--    yana geçen süre eklenir, en çok 15 sn; ilk nabız sayacı başlatır (son_nabiz boşken süre eklenmez).
-- 2) finish_attempt_tx: nabız gelmişse resmi süre aktif_ms + min(şimdi − son_nabiz, 15 sn); hiç gelmemişse (eski istemci)
--    duvar saati, davranış eskisi gibi. Süre aşımı (günün sonu, K101) duvar saatiyle kalır.
-- 3) count_hint: nabızlı denemede son nabız 15 sn'den eskiyse 'duraklatildi' (ipucu yazılmaz, hak düşmez).

alter table sezgi.attempts
  add column if not exists aktif_ms int not null default 0,
  add column if not exists son_nabiz timestamptz;

create function sezgi.nabiz(p_attempt bigint) returns jsonb
language plpgsql security definer set search_path = sezgi as $$
declare u uuid := auth.uid(); r record;
begin
  if u is null then raise exception 'giris_gerekli'; end if;
  if not ortak.hiz_siniri('sezgi-nabiz:' || u, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  update attempts a set
    aktif_ms = case when a.son_nabiz is null then a.aktif_ms
                    else a.aktif_ms + least(15000, greatest(0, (extract(epoch from now() - a.son_nabiz) * 1000)::int)) end,
    son_nabiz = now()
  from daily_puzzles p
  where a.id = p_attempt and a.user_id = u and p.id = a.puzzle_id and a.status = 'started' and now() < attempt_deadline(p.day)
  returning a.aktif_ms into r;
  if not found then return jsonb_build_object('error', 'attempt_closed'); end if;
  return jsonb_build_object('aktif_ms', r.aktif_ms);
end $$;
revoke all on function sezgi.nabiz(bigint) from public, anon;
grant execute on function sezgi.nabiz(bigint) to authenticated;

create or replace function sezgi.finish_attempt_tx(
  p_attempt bigint, p_user uuid, p_value double precision, p_score int, p_solution jsonb,
  p_client_ms int, p_min_ms int, p_beaten boolean, p_retried boolean, p_reached boolean
) returns jsonb language plpgsql set search_path = sezgi set extra_float_digits = 1 as $$
declare
  a attempts;
  p daily_puzzles;
  already boolean;
  ms int;
  fl text[] := '{}';
begin
  select * into a from attempts where id = p_attempt and user_id = p_user for update;
  if not found then return jsonb_build_object('error', 'attempt_not_found'); end if;
  select * into p from daily_puzzles where id = a.puzzle_id;
  already := a.status <> 'started';
  if not already then
    if now() >= attempt_deadline(p.day) then
      update attempts set status = 'timeout', score = 0,
        duration_ms = round(extract(epoch from attempt_deadline(p.day) - a.started_at) * 1000)::int
      where id = a.id returning * into a;
    else
      -- Nabız geldiyse ekranda geçen süre (duraklatma sayılmaz), gelmediyse duvar saati.
      ms := case when a.son_nabiz is not null
                 then a.aktif_ms + least(15000, greatest(0, round(extract(epoch from now() - a.son_nabiz) * 1000)::int))
                 else round(extract(epoch from now() - a.started_at) * 1000)::int end;
      if ms < p_min_ms then fl := array_append(fl, 'too_fast'); end if;
      if p_client_ms is not null and abs(ms - p_client_ms) > 10000 then fl := array_append(fl, 'clock_mismatch'); end if;
      if p_retried then fl := array_append(fl, 'connection_lost'); end if;
      if p.day < istanbul_today() then fl := array_append(fl, 'after_day_end'); end if;
      update attempts set status = 'submitted', submitted_at = now(), duration_ms = ms, client_ms = p_client_ms,
        value = p_value, score = p_score, solution = p_solution, flags = fl,
        reached = case when p.kind = 'race' then coalesce(p_reached, false) end
      where id = a.id returning * into a;
      if p_beaten then
        update daily_puzzles set target_beaten = true where id = p.id returning * into p;
      end if;
    end if;
  end if;
  return jsonb_build_object(
    'attempt_id', a.id, 'kind', p.kind, 'status', a.status, 'value', a.value, 'score', a.score,
    'duration_ms', a.duration_ms, 'submitted_at', a.submitted_at, 'flags', a.flags,
    'hints', a.hints, 'reached', a.reached,
    'target_value', p.target_value, 'greedy_value', p.greedy_value, 'target_beaten', p.target_beaten,
    'already_final', already);
end $$;

create or replace function sezgi.count_hint(p_attempt bigint, p_user uuid) returns int
language plpgsql set search_path = sezgi as $$
declare n int;
begin
  if exists (select 1 from attempts where id = p_attempt and user_id = p_user and status = 'started'
             and son_nabiz is not null and son_nabiz < now() - interval '15 seconds') then
    raise exception 'duraklatildi' using errcode = 'P0001';
  end if;
  update attempts a set hints = a.hints + 1
  from daily_puzzles p
  where a.id = p_attempt and a.user_id = p_user and p.id = a.puzzle_id and p.kind = 'race'
    and a.status = 'started' and now() < attempt_deadline(p.day) and a.hints < 3
  returning a.hints into n;
  if n is null and exists (select 1 from attempts where id = p_attempt and user_id = p_user and hints >= 3 and status = 'started') then
    raise exception 'ipucu_hakki_bitti' using errcode = 'P0001';
  end if;
  return n;
end $$;
