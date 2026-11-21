-- Göç 8110: açılmış gün koruma tetik işlevlerinde varsayılan PUBLIC yürütme hakkı kaldırılır (Advisor temizliği).
-- Tetik işlevi doğrudan çağrılamaz ve bu şemalar API'ye açık değil; risk yoktu, yalnız yetki listesi sade kalsın.
revoke execute on function ense.acilmis_gun_koru(), sahte.acilmis_gun_koru(), remzle.acilmis_gun_koru(), ezber.acilmis_gun_koru()
  from public, anon, authenticated;
