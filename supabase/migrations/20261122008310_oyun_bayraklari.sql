-- Göç 8310: oturumsuz ziyaretçiye oyunun halka açık bayrakları (Koz bulgusu, 22 Kasım). ortak.acilis yalnız oturumlu
-- (authenticated) role açık; oyunların çoğu misafire ilk açılışta Supabase oturumu açmaz (anonim giriş Turnstile ister,
-- yalnız gerekince). Önizleme kilidi ve gizleme o ziyaretçiye de uygulanmalı.
-- ortak.oyun_bayraklari(oyun): testçi olmayan birinin göreceği bayraklar (etkin_bayraklar(oyun, null)): kapali, onizleme,
-- yayin_tarihi, duyuru, asgari_surum. Yalnız ayar okur, kimlik ya da oyuncu verisi içermez; anon'a açık. Testçi bilgisi
-- yine oturumla acilis'ten gelir.

create function ortak.oyun_bayraklari(p_oyun text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select ortak.etkin_bayraklar(p_oyun, null::uuid);
$$;
revoke all on function ortak.oyun_bayraklari(text) from public;
grant execute on function ortak.oyun_bayraklari(text) to anon, authenticated;
