-- Göç 8420 (MD-23, Mahalle 23 Kasım): deneme oyunun kendi işleminde (ör. basla) nabızsız açıldıysa ilk nabız, açılıştan
-- (olusturma) o ana kadarki süreyi saymıyordu; Mahalle istemcide max(aktifSureMs, simdi − acildi − durak_ms) ile telafi
-- ediyordu. Artık son_nabiz yoksa başvuru olusturma: boşluk 90 sn'ye kadar aktif süreye, daha uzunsa duraklamaya eklenir
-- (sonraki nabızlarla aynı kural). Nabızla açılan yeni denemede değişiklik yok (insert yolu).
create or replace function ortak.nabiz_isle(p_oyun text, p_kullanici uuid, p_anahtar text, p_durdur boolean default false)
returns ortak.denemeler
language sql security definer set search_path = '' as $$
  insert into ortak.denemeler as e (oyun_id, kullanici_id, anahtar, son_nabiz, durdu)
    values (p_oyun, p_kullanici, p_anahtar, now(), false)
    on conflict (oyun_id, kullanici_id, anahtar) do update set
      aktif_ms = case when e.bitti or e.durdu or now() - coalesce(e.son_nabiz, e.olusturma) > interval '90 seconds' then e.aktif_ms
                      else e.aktif_ms + greatest(0, (extract(epoch from now() - coalesce(e.son_nabiz, e.olusturma)) * 1000)::bigint) end,
      durak_ms = case when not e.bitti and (e.durdu or now() - coalesce(e.son_nabiz, e.olusturma) > interval '90 seconds')
                      then e.durak_ms + greatest(0, (extract(epoch from now() - coalesce(e.son_nabiz, e.olusturma)) * 1000)::bigint)
                      else e.durak_ms end,
      son_nabiz = case when e.bitti then e.son_nabiz else now() end,
      durdu = case when e.bitti then e.durdu else coalesce(p_durdur, false) end
  returning *
$$;
revoke execute on function ortak.nabiz_isle(text, uuid, text, boolean) from public, anon, authenticated;
