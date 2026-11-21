-- Ezber Bozan lig, ilk sezon (kurucu kararı, dış değerlendirme sonrası): grup 20 kişi, ilk 4 (%20) çıkar, kimse inmez
-- (inis_orani 0: kapanışta floor(n*0) = 0 kişi iner). Kademe atlayana albüm ödülü sira:lig-<n>-<hafta> (kademe_odulu).
-- İniş sonradan, ilk sezon bitince ayrı göçle açılır. Açık grupların boyu değişmez; yeni atamalar 20'lik gruba gider.
update ortak.oyunlar
   set ayarlar = jsonb_set(ayarlar, '{lig}', (ayarlar -> 'lig') || '{"grup_boyu":20,"cikis_orani":0.2,"inis_orani":0,"kademe_odulu":true}'::jsonb)
 where id = 'ezber';
