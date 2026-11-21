-- Eski Halka hak tablosu (Security/Performance Advisor bulgusu, 19 Kasım). Halka kodunda hiç geçmiyor (Halka oturumu
-- doğruladı; haklar ortak.haklar'da), canlıda ve testte 0 satır. Tablo kaldırılır. halka.oyuncu_verisini_sil oyunun
-- silme işlevi olarak ortak.oyun_verisini_sil'den çağrılmaya devam ettiği için kalır; Halka'ya özgü silinecek veri yok.

create or replace function halka.oyuncu_verisini_sil(u uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  null; -- Halka'nın kendi tablolarında kullanıcı verisi yok (haklar, skorlar, kayıt ortak şemada silinir).
end $$;
revoke execute on function halka.oyuncu_verisini_sil(uuid) from public, anon, authenticated;

drop table if exists public.hk_entitlements;
