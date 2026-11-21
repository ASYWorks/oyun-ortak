-- Ezber Bozan haftalık lig ayarı (kurucu kararı, ezber LIVEOPS §9b ve Y29): lig puanı günlük puandır, haftanın en iyi
-- 5 günü sayılır, yardımlı oyun sayılmaz (dogrula-ezber yardımlıda ligPuani göndermez). 50 kişilik grupta %10 çıkış/iniş.
update ortak.oyunlar
   set ayarlar = jsonb_set(ayarlar, '{lig}', '{"kademeler":["Çırak","Kalfa","Usta","Hayalî"],"grup_boyu":50,"cikis_orani":0.1,"inis_orani":0.1,"en_iyi_gun":5,"esitlik":"ikincil","bant_genisligi":0}'::jsonb, true)
 where id = 'ezber';
