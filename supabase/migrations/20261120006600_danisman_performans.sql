-- Supabase Performance Advisor (19 Kasım, kurucu isteği; test ve canlıda aynı bulgular).
-- 1) auth_rls_initplan: politikalar auth.uid()'i her satır için yeniden hesaplıyordu. (select auth.uid()) sorgu başına bir
--    kez hesaplanır; anlam aynı (aynı oturum, aynı değer). Erişim kapsamı değişmez.
-- 2) unindexed_foreign_keys: kullanıcıya bağlı yabancı anahtarlarda indeks yoktu; hesap silme ve 90 günlük misafir
--    temizliği (auth.users silinince cascade) bu tabloları baştan sona tarıyordu. ortak.urunler.oyun_id eklenmedi
--    (birkaç satır, oyun silinmez).
-- Bilerek bırakılanlar: skorlar_sira (6100'le yeni, sıralamada kullanılıyor), sezgi.game_sign search_path (tabloya
-- başvurmayan saf işlev; SET verilirse sıralama görünümlerinde satır başına çağrı gömülemez).

alter policy "kendi hakkını oku" on public.hk_entitlements using (user_id = (select auth.uid()));
alter policy attempts_read on sezgi.attempts using (user_id = (select auth.uid()));
alter policy leagues_delete on sezgi.leagues using (owner_id = (select auth.uid()));
alter policy leagues_insert on sezgi.leagues with check (owner_id = (select auth.uid()));
alter policy leagues_read on sezgi.leagues using (owner_id = (select auth.uid()) or sezgi.is_league_member(id));
alter policy leagues_update on sezgi.leagues using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
alter policy level_progress_own on sezgi.level_progress using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
alter policy level_verified_read on sezgi.level_verified using (user_id = (select auth.uid()));
alter policy profiles_insert on sezgi.profiles with check (id = (select auth.uid()));
alter policy profiles_update on sezgi.profiles using (id = (select auth.uid())) with check (id = (select auth.uid()));
alter policy tutorial_progress_own on sezgi.tutorial_progress using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create index if not exists bildirim_anahtarlari_kullanici on ortak.bildirim_anahtarlari (kullanici_id);
create index if not exists bildirim_gonderimleri_kullanici on ortak.bildirim_gonderimleri (kullanici_id);
create index if not exists devirler_anonim on ortak.devirler (anonim_id);
create index if not exists kayitlar_kullanici on ortak.kayitlar (kullanici_id);
create index if not exists sikayetler_hedef on ortak.sikayetler (hedef);
create index if not exists sikayetler_sikayet_eden on ortak.sikayetler (sikayet_eden);
create index if not exists leagues_owner on sezgi.leagues (owner_id);
