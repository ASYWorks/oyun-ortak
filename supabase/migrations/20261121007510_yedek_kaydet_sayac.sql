-- 7500 düzeltmesi (güvenlik taraması): yedek_kaydet yanlış anahtarda hata fırlatınca işlem geri alınıyor ve hız sınırı
-- sayacı da geri alınıyordu; bu yoldan yapılan denemeler sayılmıyordu. Artık hata yerine false döner (sayaç kalır),
-- doğru anahtarda true. Panel anahtarı 256 bit rastgele (openssl rand -hex 32).
drop function ortak.yedek_kaydet(text, text, boolean, bigint, text);
create function ortak.yedek_kaydet(p_anahtar text, p_proje text, p_basarili boolean, p_boyut bigint, p_not text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if not ortak.panel_hiz() then return false; end if;
  if not ortak.panel_anahtar_dogru(p_anahtar) then return false; end if;
  insert into ortak.yedek_kayitlari (proje, basarili, boyut_bayt, "not") values (p_proje, p_basarili, p_boyut, left(p_not, 200));
  return true;
end $$;
revoke all on function ortak.yedek_kaydet(text, text, boolean, bigint, text) from public;
grant execute on function ortak.yedek_kaydet(text, text, boolean, bigint, text) to anon, authenticated, service_role;
