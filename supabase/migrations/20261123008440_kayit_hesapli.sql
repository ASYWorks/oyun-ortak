-- Göç 8440 (MD-24): hesap doğrulamalı bulut kaydı. İstemci birleştirmeyi beklenen hesap (`kim`) için başlatınca okuma ve yazma
-- bu iki işlevle yapılır; sunucu her çağrıda oturumdaki kullanıcının beklenen hesap olduğunu doğrular. Böylece iki istek arasında
-- oturum başka hesaba geçerse (ya da geri dönerse) başka kullanıcının kaydı okunmaz, birleştirilmez, yazılmaz.
-- Ekleyici: ortak.kayit_oku(text) ve ortak.kayit_yaz(text, jsonb, integer) imzaları ve eski tüketiciler aynen kalır; yeni işlevler
-- denetimden sonra onlara devreder (anonim/kalıcı şartı, 256 KB sınırı ve iyimser kilit eski uygulamada kalır).
-- Ret: oturum yok → 'giris_gerekli' (28000, ortak.kim ile aynı); beklenen hesap boş ya da farklı → 'hesap_degisti' (42501).

create function ortak.kayit_hesap_denetle(p_kim uuid) returns void
language plpgsql stable set search_path = '' as $$
declare u uuid := ortak.kim();
begin
  if p_kim is null or p_kim <> u then raise exception 'hesap_degisti' using errcode = '42501'; end if;
end $$;

create function ortak.kayit_oku_hesapli(p_oyun text, p_kim uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ortak.kayit_hesap_denetle(p_kim);
  return ortak.kayit_oku(p_oyun);
end $$;

create function ortak.kayit_yaz_hesapli(p_oyun text, p_veri jsonb, p_surum integer, p_kim uuid) returns integer
language plpgsql security definer set search_path = '' as $$
begin
  perform ortak.kayit_hesap_denetle(p_kim);
  return ortak.kayit_yaz(p_oyun, p_veri, p_surum);
end $$;

revoke all on function ortak.kayit_hesap_denetle(uuid) from public, anon, authenticated;
revoke all on function ortak.kayit_oku_hesapli(text, uuid), ortak.kayit_yaz_hesapli(text, jsonb, integer, uuid) from public, anon;
grant execute on function ortak.kayit_oku_hesapli(text, uuid), ortak.kayit_yaz_hesapli(text, jsonb, integer, uuid) to authenticated;

revoke execute on all functions in schema ortak from public;
