-- BG-12 (Beat Greedy, 15 Kasım 2026; kurucu onayı): misafir sıralama tablolarını salt okunur görür, "sen" satırı yok
-- (ortak kural A17: misafire sıralama gösterilebilir, misafir girmez). anon'a yalnız gösterilecek sütunlar açılır;
-- user_id açılmaz (UUID'ler misafire görünmesin). İstemci sütunları adıyla seçer (select=* anon'da reddedilir).
-- Lig tabloları (league_board_*) hesaplı kalır.
grant select (game, day, username, avatar, score, duration_ms, submitted_at, rank, value) on sezgi.board_game_day to anon;
grant select (day, username, avatar, total, total_ms, games, rank) on sezgi.board_day to anon;
grant select (week_start, username, avatar, total, total_ms, days, rank) on sezgi.board_week to anon;
grant select (username, avatar, total, total_ms, days, rank) on sezgi.board_all_time to anon;
grant select (day, game, username, avatar, value, duration_ms, hints, reached, race_ms, submitted_at, rank) on sezgi.board_race to anon;
grant select (day, username, avatar, goals, race_ms, games, rank) on sezgi.board_race_day to anon;
grant select (game, username, avatar, stars, master3, reached_at, rank) on sezgi.board_levels to anon;
-- Tablolar sıralamada sezgi.game_sign çağırır; görünümdeki işlev çağrısı sorgulayan rolle çalıştığı için anon'a da açılır (yan etkisiz, oyun adından ±1).
grant execute on function sezgi.game_sign(text) to anon;
