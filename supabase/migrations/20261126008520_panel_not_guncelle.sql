-- Göç 8520: panel notu düzenleme (kurucu panel notu 18, 26 Kasım). Yapılmamış not (yeni ya da gönderilmiş) düzenlenebilir;
-- düzenlenen not yeniden "yeni" olur, oyun-ortak oturumu onu bir sonraki okumada yeniden iletir. Yapılmış not değişmez.
create function ortak.panel_not_guncelle(p_anahtar text, p_id bigint, p_metin text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if not ortak.panel_hiz() then raise exception 'cok_istek' using errcode = '54000'; end if;
  if not ortak.panel_anahtar_dogru(p_anahtar) then return null; end if;
  update ortak.panel_notlar set metin = btrim(p_metin), durum = 'yeni', gonderildi = null
   where id = p_id and durum in ('yeni', 'gonderildi');
  return found;
end $$;
revoke all on function ortak.panel_not_guncelle(text, bigint, text) from public;
grant execute on function ortak.panel_not_guncelle(text, bigint, text) to anon, authenticated, service_role;
