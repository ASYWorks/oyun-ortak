-- Yük (19 Kasım ölçümü, kurucu "sayıyı artırmak için yapabileceklere bakalım"): Nano'da darboğaz sorgu süresi değil istek
-- sayısı (nabız ve kontrol veritabanında ~0,3 ms; istek başına sabit maliyet ve kuyruk baskın). Oyun sırasında her hamle
-- zaten kontrol isteği atıyor: kontrol artık nabız da sayılır, istemci son 20 sn'de kontrol gittiyse nabız göndermez
-- (src/siralama nabizBaslat(...).dokundu()). Süre kuralı değişmedi (5600: 90 sn'ye kadar tam, uzun boşluk durak_ms'e).

-- Nabız yazımı tek yerde: ortak.nabiz (istemci) ve oyunların ilk temas / kontrol işlevleri kullanır.
create function ortak.nabiz_isle(p_oyun text, p_kullanici uuid, p_anahtar text, p_durdur boolean default false)
returns ortak.denemeler
language sql security definer set search_path = '' as $$
  insert into ortak.denemeler as e (oyun_id, kullanici_id, anahtar, son_nabiz, durdu)
    values (p_oyun, p_kullanici, p_anahtar, now(), false)
    on conflict (oyun_id, kullanici_id, anahtar) do update set
      aktif_ms = case when e.bitti or e.son_nabiz is null or e.durdu or now() - e.son_nabiz > interval '90 seconds' then e.aktif_ms
                      else e.aktif_ms + greatest(0, (extract(epoch from now() - e.son_nabiz) * 1000)::bigint) end,
      durak_ms = case when not e.bitti and e.son_nabiz is not null and (e.durdu or now() - e.son_nabiz > interval '90 seconds')
                      then e.durak_ms + greatest(0, (extract(epoch from now() - e.son_nabiz) * 1000)::bigint)
                      else e.durak_ms end,
      son_nabiz = case when e.bitti then e.son_nabiz else now() end,
      durdu = case when e.bitti then e.durdu else coalesce(p_durdur, false) end
  returning *
$$;
revoke execute on function ortak.nabiz_isle(text, uuid, text, boolean) from public, anon, authenticated;

create or replace function ortak.nabiz(p_oyun text, p_anahtar text, p_durdur boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); d ortak.denemeler;
begin
  if not exists (select 1 from ortak.oyunlar where id = p_oyun) then raise exception 'oyun_yok'; end if;
  if p_anahtar is null or char_length(p_anahtar) not between 1 and 128 then raise exception 'gecersiz'; end if;
  if not ortak.hiz_siniri('nabiz:' || u, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  d := ortak.nabiz_isle(p_oyun, u, p_anahtar, p_durdur);
  return jsonb_build_object('aktif_ms', d.aktif_ms, 'durak_ms', d.durak_ms, 'bitti', d.bitti, 'durdu', d.durdu);
end $$;

-- Halka: bugünün ve turnuvanın kontrolü ilk temasla birlikte nabız da sayar (kontrol ancak tahta açıkken gider).
create or replace function halka.ilk_temas(p_anahtar text) returns void
language plpgsql security definer set search_path = '' as $$
declare u uuid := auth.uid();
begin
  if u is null or ortak.anonim() then raise exception 'hesap_gerekli' using errcode = '28000'; end if;
  perform ortak.nabiz_isle('halka', u, p_anahtar, false);
end $$;
