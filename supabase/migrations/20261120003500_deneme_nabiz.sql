-- Duraklatılabilir sıralama süresi (Halka isteği; kurucu 16 Kasım 2026: "Duraklatmaya izin verilsin"; ADIL_PUAN §1.2).
-- Süre yalnız oyuncu bulmaca ekranındayken akar. İstemci ekran görünürken düzenli nabız gönderir (siralama
-- nabizBaslat, 10 sn). Her nabızda aktif_ms, önceki nabızdan bu yana geçen süre kadar artar, ama en çok 15 sn:
-- duraklayınca nabız gelmez ve aradaki süre sayılmaz. Sık nabız süreyi şişiremez (gerçek geçen süreden fazlası
-- eklenmez). İlk nabız denemeyi açar. Gönderimde süre = aktif_ms + min(şimdi − son_nabiz, 15 sn) (sunucu/mod.ts
-- aktifSureMs). Nabızsız eski istemci için oyun duvar saatini yedek kullanır (son_nabiz boş).

alter table ortak.denemeler
  add column if not exists aktif_ms bigint not null default 0,
  add column if not exists son_nabiz timestamptz;

create function ortak.nabiz(p_oyun text, p_anahtar text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); d ortak.denemeler;
begin
  if not exists (select 1 from ortak.oyunlar where id = p_oyun) then raise exception 'oyun_yok'; end if;
  if p_anahtar is null or char_length(p_anahtar) not between 1 and 128 then raise exception 'gecersiz'; end if;
  if not ortak.hiz_siniri('nabiz:' || u, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  insert into ortak.denemeler as e (oyun_id, kullanici_id, anahtar, son_nabiz)
    values (p_oyun, u, p_anahtar, now())
    on conflict (oyun_id, kullanici_id, anahtar) do update set
      aktif_ms = case when e.bitti or e.son_nabiz is null then e.aktif_ms
                      else e.aktif_ms + least(15000, greatest(0, (extract(epoch from now() - e.son_nabiz) * 1000)::bigint)) end,
      son_nabiz = case when e.bitti then e.son_nabiz else now() end
    returning * into d;
  return jsonb_build_object('aktif_ms', d.aktif_ms, 'bitti', d.bitti);
end $$;
revoke execute on function ortak.nabiz(text, text) from public, anon;
grant execute on function ortak.nabiz(text, text) to authenticated;
