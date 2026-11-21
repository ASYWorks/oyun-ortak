-- Saklı adı sorma (Beat Greedy isteği, 17 Kasım 2026). Beat Greedy'de oyuncu satırı profil açılırken açılır; silinip
-- yeniden açan, ad kilidi sürerken (20261120004300) ad seçme ekranını görmeden eski adıyla devam etsin diye istemci
-- önce saklı adını sorar ve profili o adla açar. Yalnız çağıranın kendi giriş kimliği özetiyle eşleşen ad döner; ad o
-- oyunda başka oyuncudaysa dönmez. Satır silinmez: ad, oyuncu satırı açılınca silinen_ad_geri'de geri gelir.
create function ortak.sakli_ad(p_oyun text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare s ortak.silinen_adlar;
begin
  if ortak.anonim() then return null; end if;
  if not exists (select 1 from ortak.silinen_adlar where oyun_id = p_oyun and bitis > now()) then return null; end if;
  select * into s from ortak.silinen_adlar
    where oyun_id = p_oyun and bitis > now() and ozet = any (ortak.kimlik_ozetleri(ortak.kim()))
    order by ad_degisti desc limit 1;
  if not found or exists (select 1 from ortak.oyuncular where oyun_id = p_oyun and ad_anahtari = s.ad_anahtari) then
    return null;
  end if;
  return jsonb_build_object('ad', s.ad, 'kalan_gun', ceil(extract(epoch from (s.bitis - now())) / 86400));
end $$;
revoke execute on function ortak.sakli_ad(text) from public, anon;
grant execute on function ortak.sakli_ad(text) to authenticated;
