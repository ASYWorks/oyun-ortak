-- Göç 8330: testçi korumalı içeriğe de erişir (Halka HK-32, 23 Kasım). ONIZLEME: testçi (kurucu) her zaman bütün içeriği
-- görür; ücretli seviyeler korumali kovasından ortak.hakki_var ile iner, ama hakki_var testçiyi tanımıyordu. Testçi her hakkı
-- taşıyor sayılır; haklar listesine (haklarim) dokunulmaz, satır yazılmaz.

create or replace function ortak.hakki_var(p_oyun text, p_hak text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from ortak.haklar
                  where oyun_id = p_oyun and hak = p_hak and kullanici_id = auth.uid() and durum = 'aktif')
      or exists (select 1 from ortak.testciler where kullanici_id = auth.uid())
$$;
