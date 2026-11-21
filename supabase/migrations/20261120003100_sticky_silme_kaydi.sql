-- ST-10 düzeltmesi (güvenlik incelemesi): "bu oyundan sil" puanlı oyun kaydını silmez, yalnız silinen oyuncunun
-- satırını çıkarır. Kayıt kalır: sunucu aynı oyun kimliğini 7 gün içinde yeniden gönderirse öbür oyunculara ikinci
-- kez yazılmaz.
create or replace function sticky.oyuncu_verisini_sil(u uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from sticky.stats where user_id = u;
  delete from sticky.rating_log where user_id = u;
  delete from sticky.rated_pairs where position(u::text in pair) > 0;
  delete from sticky.follows where user_id = u or follows_id = u;
  update sticky.puanli_oyunlar
     set sonuc = (select coalesce(jsonb_agg(e), '[]') from jsonb_array_elements(sonuc) e where e ->> 'kullanici' <> u::text)
   where sonuc @> jsonb_build_array(jsonb_build_object('kullanici', u));
end $$;
