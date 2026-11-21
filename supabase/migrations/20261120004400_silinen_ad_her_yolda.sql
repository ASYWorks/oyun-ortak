-- 20261120004300 düzeltmesi (güvenlik incelemesi, 17 Kasım 2026): saklı ad kilidi bütün ad yazma yollarında.
-- 1) Saklı ad, kilit sürerken başkasına hiçbir yoldan verilmez: ortak.oyuncular'da ad anahtarı değişirken saklı adla
--    çakışırsa benzersizlik hatası (23505) verilir; ad_degistir ve sezgi.ad_denetle bunu zaten 'alinmis' sayar.
-- 2) Beat Greedy (sezgi.ad_denetle) bekleme kuralını yalnız profil güncellemesinde uyguluyordu. Silip yeniden açan
--    profil açarken (INSERT) saklı adı geri gelmiş satırı yeni adla ezip kilidi atlatabiliyordu. Artık her durumda
--    uygulanır; aynı adı yeniden seçen engellenmez.

create function ortak.silinen_ad_tutulu() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.ad_anahtari is not null and new.ad_anahtari is distinct from old.ad_anahtari
     and exists (select 1 from ortak.silinen_adlar
                 where oyun_id = new.oyun_id and ad_anahtari = new.ad_anahtari and bitis > now()) then
    raise exception 'ad_tutulu' using errcode = '23505';
  end if;
  return new;
end $$;
create trigger silinen_ad_tutulu before update of ad_anahtari on ortak.oyuncular
  for each row execute function ortak.silinen_ad_tutulu();
revoke execute on function ortak.silinen_ad_tutulu() from public, anon, authenticated;

create or replace function sezgi.ad_denetle() returns trigger
language plpgsql security definer set search_path = '' as $$
declare a jsonb; o ortak.oyuncular; gun int; v text := new.username::text;
begin
  -- Şikâyetle sıfırlamanın kendi yazdığı yer tutucu ad denetlenmez ve ortağa yansımaz.
  if current_setting('ortak.ad_yansitma', true) = 'kapali' then return new; end if;
  if tg_op = 'UPDATE' and new.username is not distinct from old.username then return new; end if;
  if ortak.anonim() then raise exception 'kalici_hesap_gerekli' using errcode = 'P0001'; end if;

  select coalesce(ayarlar -> 'ad', '{}') into a from ortak.oyunlar where id = 'sezgi';
  if not ortak.ad_bicimi(v, coalesce((a ->> 'en_az')::int, 3), coalesce((a ->> 'en_cok')::int, 20))
     or not ortak.ad_uygun(v, coalesce(array(select jsonb_array_elements_text(a -> 'yasakli')), '{}'))
     or exists (select 1 from ortak.engelli_adlar where oyun_id = 'sezgi' and ad_anahtari = ortak.ad_anahtari(v)) then
    raise exception 'ad_uygunsuz' using errcode = 'P0001';
  end if;

  insert into ortak.oyuncular (oyun_id, kullanici_id) values ('sezgi', new.id) on conflict do nothing;
  select * into o from ortak.oyuncular where oyun_id = 'sezgi' and kullanici_id = new.id for update;
  gun := coalesce((a ->> 'degistirme_gun')::int, 30);
  -- Silinip yeniden açılan hesapta saklı ad geri gelmiş olabilir (20261120004300): aynı adsa dokunma, başkasıysa kilit.
  if o.ad_anahtari is not distinct from ortak.ad_anahtari(v) and not o.ad_otomatik then return new; end if;
  if o.ad_degisti is not null and o.ad_degisti > now() - make_interval(days => gun) then
    raise exception 'ad_bekle' using errcode = 'P0001',
      hint = ceil(extract(epoch from (o.ad_degisti + make_interval(days => gun) - now())) / 86400)::text;
  end if;

  begin
    update ortak.oyuncular set ad = v, ad_anahtari = ortak.ad_anahtari(v), ad_otomatik = false, ad_degisti = now()
      where oyun_id = 'sezgi' and kullanici_id = new.id;
  exception when unique_violation then
    raise exception 'ad_alinmis' using errcode = 'P0001';
  end;
  return new;
end $$;
