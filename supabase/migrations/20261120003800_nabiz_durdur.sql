-- Duraklatma cezasız (16 Kasım 2026): 3500/3700'de duraklatıp dönen oyuncunun ilk nabzı aradaki süreden en çok 15 sn ekliyordu
-- (her duraklatma ~15 sn ceza). Çözüm: istemci duraklatırken "durdur" nabzı gönderir; sunucu o ana kadarki süreyi ekler ve
-- sayacı durdurur (durdu). Devam nabzı süre eklemeden sayacı yeniden başlatır. Durdur nabzı gelmeyen (uygulama kapandı,
-- ağ koptu) aralıklar eskisi gibi en çok 15 sn sayılır. Durmuş denemede ipucu yok; bitirmede süre aktif_ms.
-- Ortak (ortak.denemeler, ortak.nabiz, Halka) ve Beat Greedy (sezgi.attempts, sezgi.nabiz) aynı biçimde.

alter table ortak.denemeler add column if not exists durdu boolean not null default false;
alter table sezgi.attempts add column if not exists durdu boolean not null default false;

drop function ortak.nabiz(text, text);
create function ortak.nabiz(p_oyun text, p_anahtar text, p_durdur boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); d ortak.denemeler;
begin
  if not exists (select 1 from ortak.oyunlar where id = p_oyun) then raise exception 'oyun_yok'; end if;
  if p_anahtar is null or char_length(p_anahtar) not between 1 and 128 then raise exception 'gecersiz'; end if;
  if not ortak.hiz_siniri('nabiz:' || u, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  insert into ortak.denemeler as e (oyun_id, kullanici_id, anahtar, son_nabiz, durdu)
    values (p_oyun, u, p_anahtar, now(), coalesce(p_durdur, false))
    on conflict (oyun_id, kullanici_id, anahtar) do update set
      aktif_ms = case when e.bitti or e.son_nabiz is null or e.durdu then e.aktif_ms
                      else e.aktif_ms + least(15000, greatest(0, (extract(epoch from now() - e.son_nabiz) * 1000)::bigint)) end,
      son_nabiz = case when e.bitti then e.son_nabiz else now() end,
      durdu = case when e.bitti then e.durdu else coalesce(p_durdur, false) end
    returning * into d;
  return jsonb_build_object('aktif_ms', d.aktif_ms, 'bitti', d.bitti, 'durdu', d.durdu);
end $$;
revoke execute on function ortak.nabiz(text, text, boolean) from public, anon;
grant execute on function ortak.nabiz(text, text, boolean) to authenticated;

drop function sezgi.nabiz(bigint);
create function sezgi.nabiz(p_attempt bigint, p_durdur boolean default false) returns jsonb
language plpgsql security definer set search_path = sezgi as $$
declare u uuid := auth.uid(); r record;
begin
  if u is null then raise exception 'giris_gerekli'; end if;
  if not ortak.hiz_siniri('sezgi-nabiz:' || u, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  update attempts a set
    aktif_ms = case when a.son_nabiz is null or a.durdu then a.aktif_ms
                    else a.aktif_ms + least(15000, greatest(0, (extract(epoch from now() - a.son_nabiz) * 1000)::int)) end,
    son_nabiz = now(),
    durdu = coalesce(p_durdur, false)
  from daily_puzzles p
  where a.id = p_attempt and a.user_id = u and p.id = a.puzzle_id and a.status = 'started' and now() < attempt_deadline(p.day)
  returning a.aktif_ms, a.durdu into r;
  if not found then return jsonb_build_object('error', 'attempt_closed'); end if;
  return jsonb_build_object('aktif_ms', r.aktif_ms, 'durdu', r.durdu);
end $$;
revoke all on function sezgi.nabiz(bigint, boolean) from public, anon;
grant execute on function sezgi.nabiz(bigint, boolean) to authenticated;

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
      ms := case when a.son_nabiz is null then round(extract(epoch from now() - a.started_at) * 1000)::int
                 when a.durdu then a.aktif_ms
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

create or replace function sezgi.count_hint(p_attempt bigint, p_user uuid) returns int
language plpgsql set search_path = sezgi as $$
declare n int;
begin
  if exists (select 1 from attempts where id = p_attempt and user_id = p_user and status = 'started'
             and (durdu or (son_nabiz is not null and son_nabiz < now() - interval '15 seconds'))) then
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

create or replace function halka.ipucu_ver(p_anahtar text, p_halkalar jsonb, p_cevaplar text[], p_cozum jsonb, p_anlamlar jsonb,
                                p_kilit_sirasi integer[], p_kurallar jsonb, p_tur text, p_sira integer,
                                p_rot integer[], p_flip boolean[], p_kilitli integer[], p_tema text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid();
  d ortak.denemeler;
  sira int[];
  r int;
  sonuc jsonb;
begin
  -- Duraklatılmış denemede ipucu yok: durdur nabzı geldiyse ya da nabızlı denemede son nabız 15 sn'den eskiyse.
  -- Nabızsız (eski istemci) denemede davranış aynı.
  if u is not null and exists (select 1 from ortak.denemeler e
      where e.oyun_id = 'halka' and e.kullanici_id = u and e.anahtar = p_anahtar and not e.bitti
        and (e.durdu or (e.son_nabiz is not null and e.son_nabiz < now() - interval '15 seconds'))) then
    raise exception 'duraklatildi' using errcode = 'P0001';
  end if;
  if p_tur = 'anlam' then
    sonuc := case when p_anlamlar ->> p_cevaplar[p_sira + 1] is not null
                  then jsonb_build_object('anlam', p_anlamlar ->> p_cevaplar[p_sira + 1]) end;
  elsif p_tur = 'kilit' then
    if p_cozum is null then return null; end if;
    -- Hak (src/puan.ts IPUCU_HAK.kilit): bitince ipucu yok (istemci pencerede satırı kapatır; dogrula-halka fazlasını 422 ile reddeder).
    if u is not null then
      perform 1 from ortak.denemeler where oyun_id = 'halka' and kullanici_id = u and anahtar = p_anahtar for update;
    end if;
    if u is not null and (select count(*) from ortak.denemeler e, jsonb_array_elements_text(coalesce(e.durum -> 'ipuclari', '[]')) x
                          where e.oyun_id = 'halka' and e.kullanici_id = u and e.anahtar = p_anahtar and x = 'kilit') >= 2 then
      return null;
    end if;
    if p_rot is not null or p_flip is not null then
      if not halka.durum_gecerli(jsonb_array_length(p_halkalar), p_rot, p_flip) then
        raise exception 'gecersiz_durum' using errcode = '22023';
      end if;
      d := ortak.deneme_al('halka', u, p_anahtar);
      sonuc := halka.kilit_sec(p_halkalar, p_cozum, p_kurallar,
        array(select jsonb_array_elements_text(coalesce(p_kurallar -> 'locked', '[]'))::int)
          || case when p_kilitli is not null then array(select x from unnest(p_kilitli) x where x is not null)
                  else array(select jsonb_array_elements_text(coalesce(d.durum -> 'kilitli', '[]'))::int) end,
        p_kilit_sirasi, p_rot, p_flip);
    else
      sira := coalesce(p_kilit_sirasi, '{}')
        || array(select g from generate_series(0, jsonb_array_length(p_halkalar) - 1) g
                 where g <> all (coalesce(p_kilit_sirasi, '{}')) order by g);
      r := sira[p_sira + 1];
      if r is not null then
        sonuc := jsonb_build_object('halka', r, 'rot', p_cozum -> 'rot' -> r, 'flip', p_cozum -> 'flip' -> r);
      end if;
    end if;
  elsif p_tur = 'tema' then
    sonuc := jsonb_strip_nulls(jsonb_build_object('tema', p_tema));
  else
    raise exception 'gecersiz_tur' using errcode = '22023';
  end if;
  if sonuc is not null and u is not null then
    d := ortak.deneme_al('halka', u, p_anahtar);
    -- Tema ipucu bir kez sayılır: başlığı kaybeden istemci yeniden isteyebilir.
    if not (p_tur = 'tema' and coalesce(d.durum -> 'ipuclari', '[]'::jsonb) ? 'tema') then
      update ortak.denemeler
         set durum = durum || jsonb_build_object('ipuclari', coalesce(durum -> 'ipuclari', '[]'::jsonb) || to_jsonb(p_tur))
                   || case when p_tur = 'kilit' and not coalesce(durum -> 'kilitli', '[]'::jsonb) @> jsonb_build_array(sonuc -> 'halka')
                           then jsonb_build_object('kilitli', coalesce(durum -> 'kilitli', '[]'::jsonb) || (sonuc -> 'halka'))
                           else '{}'::jsonb end,
             guncelleme = now()
       where oyun_id = 'halka' and kullanici_id = u and anahtar = p_anahtar and not bitti;
    end if;
  end if;
  return sonuc;
end $$;
