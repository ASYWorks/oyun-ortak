-- O1 (Halka, 15 Kasım 2026): Halka istemcisi açılış, oyun ve hata kayıtlarını artık PostHog'a gönderiyor (92781bc);
-- eski ölçüm tabloları ve onlara bağlı görünüm, tetikleyici ve işlev kaldırılır. Kayıtlar arşivlenmez: kimliksiz
-- cihaz kayıtlarıydı ve gizlilik metninde en çok 1 yıl / 30 gün tutulacakları yazılıydı; silmek daha az veri tutmak.
drop view if exists public.hk_retention;
drop view if exists public.hk_funnel;
drop table if exists public.hk_opens;
drop table if exists public.hk_plays;
drop table if exists public.hk_errors;
drop function if exists public.hk_throttle();
