-- Halka'nın RevenueCat Play uygulaması (18 Kasım 2026). odeme-webhook TRANSFER olayında
-- uygulama kimliğini oyuna bu diziden eşler (ortak.hak_aktar). Tekrar çalışırsa aynı kimliği ikinci kez eklemez.
update ortak.oyunlar
set ayarlar = jsonb_set(
  ayarlar, '{odeme,revenuecat_uygulamalari}',
  coalesce(ayarlar -> 'odeme' -> 'revenuecat_uygulamalari', '[]'::jsonb) || '["app0a6c7bdf38"]'::jsonb)
where id = 'halka'
  and not coalesce(ayarlar -> 'odeme' -> 'revenuecat_uygulamalari', '[]'::jsonb) ? 'app0a6c7bdf38';
