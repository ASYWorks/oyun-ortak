-- Göç 7900: Sahte Masası oyun-ortak'a geçiyor (Upstash/Vercel bırakılıyor; canlıda 0 kayıtlı hesap, taşıma gerekmez).
-- Sözleşme: sahte-masasi/docs/DOGRULA_SOZLESME.md (dogrula-sahte-masasi, oyunun deposunda). Kararlar ISTEKLER.md SM-1..3.
-- Oyun kimliği 'sahte' (oyuncuya görünmez; oyunun adı değişse de değişmez).
-- - ortak.oyunlar 'sahte': ortak ad kuralı, günlük sıralama (büyük puan önde, eşitlikte ikincil = süre, küçük önde); lig yok.
-- - sahte.desteler: günün destesi; tam (cevaplar dahil) yalnız sunucuda, acik istemciye giden görünüm. Açılmış gün değişemez.
-- - Bölümler (hesapsız): geçmiş günlerin desteleri RPC ile; gelecek ve geç kabul penceresi açık gün (dün, 03:00'e kadar)
--   verilmez. Misafire açık, hız sınırlı. Statik pakette deste yok.

create schema if not exists sahte;
grant usage on schema sahte to service_role;
alter default privileges in schema sahte revoke all on tables from anon, authenticated, public;
alter default privileges in schema sahte revoke execute on functions from anon, authenticated, public;
alter default privileges in schema sahte grant all on tables to service_role;

insert into ortak.oyunlar (id, ad, ayarlar) values (
  'sahte', 'Sahte Masası', '{
    "ad": { "en_az": 3, "en_cok": 20, "degistirme_gun": 30 },
    "siralama": { "esitlik": "ikincil", "dagilim_esigi": 50 },
    "odeme": { "revenuecat_uygulamalari": [] }
  }'
) on conflict (id) do nothing;

create table sahte.desteler (
  gun date primary key,
  no integer not null unique,
  surum integer not null,
  tam jsonb not null,             -- cevaplar ve açılımlar dahil (istemciye yalnız açılım ucu ve bölüm olarak gider)
  acik jsonb not null,            -- açık görünüm (cevapsız)
  ozet text not null,             -- oyundaki data/acilmis.json ile aynı (sha256/16)
  yukleme timestamptz not null default now()
);
alter table sahte.desteler enable row level security; -- politika yok: yalnız servis rolü ve aşağıdaki işlevler
revoke all on sahte.desteler from public, anon, authenticated;
grant all on sahte.desteler to service_role;

create function sahte.acilmis_gun_koru() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.gun <= ortak.bugun() and coalesce(current_setting('sahte.duzeltme', true), '') <> 'evet'
     and (tg_op = 'DELETE' or (old.no, old.surum, old.tam, old.acik, old.ozet) is distinct from (new.no, new.surum, new.tam, new.acik, new.ozet)) then
    raise exception 'acilmis_gun_degisemez' using errcode = 'P0001',
      hint = 'Bilinçli düzeltme: aynı oturumda set sahte.duzeltme = ''evet''; değişiklik yönetim kaydına düşer.';
  end if;
  return coalesce(new, old);
end $$;
create trigger acilmis_gun_koru before update or delete on sahte.desteler for each row execute function sahte.acilmis_gun_koru();
create trigger yonetim_kaydi after insert or update or delete on sahte.desteler for each row execute function ortak.yonetim_kaydet('gun');

-- Bölüm olarak açılabilir mi: geçmiş gün, ama dün yalnız geç kabul penceresi (03:00 İstanbul) kapandıktan sonra.
create function sahte.bolum_acik(p_gun date) returns boolean
language sql stable set search_path = '' as $$
  select p_gun < ortak.bugun() - 1
      or (p_gun = ortak.bugun() - 1 and extract(hour from now() at time zone 'Europe/Istanbul') >= 3)
$$;

-- İstemci (misafir dahil) için hız sınırı: kullanıcı ya da IP başına dakikada 120.
create function sahte.sinir() returns void
language plpgsql set search_path = '' as $$
declare
  b json := nullif(current_setting('request.headers', true), '')::json;
  kim text := coalesce(auth.uid()::text, b ->> 'cf-connecting-ip', trim(split_part(b ->> 'x-forwarded-for', ',', 1)), 'bilinmeyen');
begin
  if not ortak.hiz_siniri('sahte:' || kim, 120, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
end $$;

-- Takvim: bugüne kadarki günler (gelecek yok). { bugun, gunler: [{gun, no, surum, bolum}] }
create function public.sahte_takvim() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform sahte.sinir();
  return jsonb_build_object('bugun', ortak.bugun(), 'gunler', coalesce((
    select jsonb_agg(jsonb_build_object('gun', d.gun, 'no', d.no, 'surum', d.surum, 'bolum', sahte.bolum_acik(d.gun)) order by d.gun)
    from sahte.desteler d where d.gun <= ortak.bugun()), '[]'::jsonb));
end $$;

-- Bölüm: geçmiş günün tam destesi (cihazda motorla, sıralamasız oynanır). Açık değilse null.
create function public.sahte_bolum(p_gun date) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform sahte.sinir();
  if not sahte.bolum_acik(p_gun) then return null; end if;
  return (select jsonb_build_object('gun', d.gun, 'no', d.no, 'surum', d.surum, 'deste', d.tam) from sahte.desteler d where d.gun = p_gun);
end $$;

-- dogrula-sahte-masasi (servis rolü): günün satırı.
create function public.sahte_deste_oku(p_gun date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('gun', d.gun, 'no', d.no, 'surum', d.surum, 'tam', d.tam, 'acik', d.acik, 'ozet', d.ozet)
  from sahte.desteler d where d.gun = p_gun
$$;

-- Yükleme (servis rolü): [{gun, no, surum, tam, acik, ozet}]. Eksik gün eklenir; var olan yalnız gelecek günde ve özet
-- değiştiyse güncellenir; açılmış güne dokunulmaz. Dönüş: { yazilan, atlanan, son_gun, kalan_gun }.
create function public.sahte_deste_yukle(p_satirlar jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare yazilan int; toplam int := jsonb_array_length(p_satirlar);
begin
  with girdi as (
    select (x ->> 'gun')::date as gun, (x ->> 'no')::int as no, (x ->> 'surum')::int as surum,
           x -> 'tam' as tam, x -> 'acik' as acik, x ->> 'ozet' as ozet
    from jsonb_array_elements(p_satirlar) x
  ), yaz as (
    insert into sahte.desteler as d (gun, no, surum, tam, acik, ozet)
    select gun, no, surum, tam, acik, ozet from girdi
    on conflict (gun) do update set no = excluded.no, surum = excluded.surum, tam = excluded.tam, acik = excluded.acik,
      ozet = excluded.ozet, yukleme = now()
      where d.gun > ortak.bugun() and d.ozet is distinct from excluded.ozet
    returning 1
  ) select count(*) into yazilan from yaz;
  return jsonb_build_object('yazilan', yazilan, 'atlanan', toplam - yazilan,
    'son_gun', (select max(gun) from sahte.desteler), 'kalan_gun', (select max(gun) - ortak.bugun() from sahte.desteler));
end $$;

revoke all on function public.sahte_takvim(), public.sahte_bolum(date), public.sahte_deste_oku(date), public.sahte_deste_yukle(jsonb) from public, anon, authenticated;
grant execute on function public.sahte_takvim(), public.sahte_bolum(date) to anon, authenticated, service_role;
grant execute on function public.sahte_deste_oku(date), public.sahte_deste_yukle(jsonb) to service_role;
revoke all on function sahte.bolum_acik(date), sahte.sinir() from public, anon, authenticated;
