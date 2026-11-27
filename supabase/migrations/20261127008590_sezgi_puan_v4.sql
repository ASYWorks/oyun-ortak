-- Göç 8590 (BG-14, kurucu K143; sezgi docs/PUAN_V4.md, ADIL_PUAN §0): Beat Greedy puan sürüm 4 kapısı. Geçiş günü
-- "ortak paketin yayınlandığı hafta" (v0.25.0, 27 Kasım): kapı bir Pazartesi olmak zorunda, geriye işlemez → 30 Kasım.
-- Formül Edge Function'da (submit_attempt, sezgi deposu; motor score.ts ile aynı); burada yalnız gün. Edge ve istemci
-- sezgi.puan_surumu(gün) okur. Eski skorlar kendi sürümünde kalır (§3.2). Kapı değişirse yalnız bu satır güncellenir.
-- Seviye puanı sunucuda zaten en çok 100 (record_level); sürüm 4'te de sürüm 3 kuralları (ilk kayıt kalıcı) geçerli.

insert into sezgi.puan_surumleri values (4, '2026-11-30') on conflict (formul) do nothing;

create function sezgi.puan_surumu(p_gun date) returns int
language sql stable security definer set search_path = '' as $$
  select coalesce(max(formul), 2) from sezgi.puan_surumleri where gecerli <= p_gun
$$;
grant execute on function sezgi.puan_surumu(date) to anon, authenticated, service_role;

-- puan_v3 "en az sürüm 3" demektir (sürüm 4'te de ilk kayıt kalıcı): tanım aynı kalır.

-- BG-12 doldurma: geçmiş Keşif ve Yarış teslimleri ortak.skorlar'a tur 'alt' satırı olarak (submit_attempt yeni teslimde
-- kendisi yazar, sezgi 904b150). Süzgeç board_day ile aynı (teslim/süre doldu, kurulum ve nabız boşluğu bayrağı yok, puanlı),
-- misafir yok. Tekrar çağrılması zararsız (ilk satır resmî, çakışan atlanır): edge yayınından sonra bir kez daha çağrılır.
create function sezgi.alt_skor_doldur() returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  insert into ortak.skorlar (oyun_id, kullanici_id, tur, donem, puan, ikincil, lig_puani, run_id, ayrinti)
  select 'sezgi', a.user_id, 'alt',
         p.day::text || ':' || p.game || ':' || case p.kind when 'race' then 'yaris' else 'kesif' end,
         a.puan, (a.ayrinti ->> 'lt')::numeric, case when p.kind = 'race' then null else a.puan end,
         gen_random_uuid(), jsonb_build_object('alt', p.game, 'doldurma', true)
  from sezgi.attempts a
  join sezgi.daily_puzzles p on p.id = a.puzzle_id
  join auth.users u on u.id = a.user_id and not u.is_anonymous
  where p.kind in ('daily', 'race') and a.status in ('submitted', 'timeout') and a.puan is not null
    and not ('kurulum' = any (a.flags)) and not ('nabiz_boslugu' = any (a.flags))
    and p.game ~ '^[a-z0-9_]{1,32}$'
  order by a.submitted_at
  on conflict (oyun_id, tur, donem, kullanici_id) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function sezgi.alt_skor_doldur() from public, anon, authenticated;
grant execute on function sezgi.alt_skor_doldur() to service_role;
select sezgi.alt_skor_doldur();
