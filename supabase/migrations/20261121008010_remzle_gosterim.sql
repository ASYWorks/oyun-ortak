-- Göç 8010 (Remzle, RZ-6): katmanın açık gösterimi de sunucuda. Bulmaca gösterimi artık Pages'te statik değil;
-- dogrula-remzle basla'da yalnız bugünün (açılmış katmanların) gösterimini verir, gelecek gün hiçbir yerde yayında olmaz.
-- Böylece önceden çözüp saniyeler içinde bitirme yolu kapanır ("cok_hizli" bayrağı yalnız iz olarak kalır; ortak sıralamaya
-- bayrak süzgeci eklenmedi).
alter table remzle.gunluk_anahtar add column gosterim jsonb not null default '{}'::jsonb;
alter table remzle.gunluk_anahtar alter column gosterim drop default;

create or replace function remzle.acilmis_gun_koru() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.gun <= ortak.bugun() and coalesce(current_setting('remzle.duzeltme', true), '') <> 'evet'
     and (tg_op = 'DELETE' or (old.cevap_ozet, old.ipuclari, old.zorluk, old.gosterim) is distinct from (new.cevap_ozet, new.ipuclari, new.zorluk, new.gosterim)) then
    raise exception 'acilmis_gun_degisemez' using errcode = 'P0001',
      hint = 'Bilinçli düzeltme: aynı oturumda set remzle.duzeltme = ''evet''; değişiklik yönetim kaydına düşer.';
  end if;
  return coalesce(new, old);
end $$;

create or replace function public.remzle_anahtar_oku(p_gun date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('katman', a.katman, 'cevap_ozet', a.cevap_ozet, 'ipuclari', a.ipuclari,
                                               'zorluk', a.zorluk, 'gosterim', a.gosterim, 'icerik_surumu', a.icerik_surumu) order by a.katman), '[]'::jsonb)
  from remzle.gunluk_anahtar a where a.gun = p_gun
$$;

create or replace function public.remzle_anahtar_yukle(p_satirlar jsonb, p_surum text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare yazilan int; toplam int := jsonb_array_length(p_satirlar);
begin
  if exists (select 1 from jsonb_array_elements(p_satirlar) x where jsonb_typeof(x -> 'gosterim') is distinct from 'object') then
    raise exception 'gosterim_gerekli' using errcode = '22023';
  end if;
  with girdi as (
    select (x ->> 'gun')::date as gun, (x ->> 'katman')::smallint as katman, x ->> 'cevap_ozet' as cevap_ozet,
           x -> 'ipuclari' as ipuclari, (x ->> 'zorluk')::smallint as zorluk, x -> 'gosterim' as gosterim
    from jsonb_array_elements(p_satirlar) x
  ), yaz as (
    insert into remzle.gunluk_anahtar as a (gun, katman, cevap_ozet, ipuclari, zorluk, gosterim, icerik_surumu)
    select gun, katman, cevap_ozet, ipuclari, zorluk, gosterim, p_surum from girdi
    on conflict (gun, katman) do update set cevap_ozet = excluded.cevap_ozet, ipuclari = excluded.ipuclari,
      zorluk = excluded.zorluk, gosterim = excluded.gosterim, icerik_surumu = excluded.icerik_surumu, yukleme = now()
      where a.gun > ortak.bugun() and a.icerik_surumu is distinct from excluded.icerik_surumu
    returning 1
  ) select count(*) into yazilan from yaz;
  return jsonb_build_object('yazilan', yazilan, 'atlanan', toplam - yazilan, 'son_gun', (select max(gun) from remzle.gunluk_anahtar));
end $$;
revoke all on function public.remzle_anahtar_oku(date), public.remzle_anahtar_yukle(jsonb, text) from public, anon, authenticated;
grant execute on function public.remzle_anahtar_oku(date), public.remzle_anahtar_yukle(jsonb, text) to service_role;
