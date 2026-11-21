-- Güvenlik incelemesi (16 Kasım 2026, 3800'e ek): durdur nabzı yalnız sayacın devamda süre eklemesini engeller.
-- 1) Teslimde durdu yok sayılır: durmuş denemede teslim de son aralığı en çok 15 sn sayar (hileli istemci "durdur" deyip
--    teslim ederek son aralığı sıfırlayamaz; dürüst oyun duraklatılmışken teslim edemez, tahta gizli).
-- 2) İlk nabız denemeyi durmuş açamaz. Halka tarafında aynı kural sunucu/sure.ts aktifSureMs'te.

create or replace function ortak.nabiz(p_oyun text, p_anahtar text, p_durdur boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); d ortak.denemeler;
begin
  if not exists (select 1 from ortak.oyunlar where id = p_oyun) then raise exception 'oyun_yok'; end if;
  if p_anahtar is null or char_length(p_anahtar) not between 1 and 128 then raise exception 'gecersiz'; end if;
  if not ortak.hiz_siniri('nabiz:' || u, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  insert into ortak.denemeler as e (oyun_id, kullanici_id, anahtar, son_nabiz, durdu)
    values (p_oyun, u, p_anahtar, now(), false)
    on conflict (oyun_id, kullanici_id, anahtar) do update set
      aktif_ms = case when e.bitti or e.son_nabiz is null or e.durdu then e.aktif_ms
                      else e.aktif_ms + least(15000, greatest(0, (extract(epoch from now() - e.son_nabiz) * 1000)::bigint)) end,
      son_nabiz = case when e.bitti then e.son_nabiz else now() end,
      durdu = case when e.bitti then e.durdu else coalesce(p_durdur, false) end
    returning * into d;
  return jsonb_build_object('aktif_ms', d.aktif_ms, 'bitti', d.bitti, 'durdu', d.durdu);
end $$;


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
      -- Teslimde durdu yok sayılır: dürüst oyun duraklatılmışken teslim edemez (tahta gizli); son aralık en çok 15 sn sayılır.
      ms := case when a.son_nabiz is null then round(extract(epoch from now() - a.started_at) * 1000)::int
                 else a.aktif_ms + least(15000, greatest(0, round(extract(epoch from now() - a.son_nabiz) * 1000)::int)) end;
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

