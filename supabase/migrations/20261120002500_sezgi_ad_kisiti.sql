-- Beat Greedy'nin eski ad kısıtı ('^[A-Za-z0-9_]{3,20}$') ortak kuralla (20261120002400) çelişiyor:
-- Türkçe harfli ya da noktalı ad tetikleyiciden geçse bile reddediliyordu. Ad biçimini artık yalnız
-- sezgi.ad_denetle tetikleyicisi (ortak.ad_bicimi) denetler; şikâyet sıfırlamasının yer tutucusu da kurala uyar.
alter table sezgi.profiles drop constraint if exists username_format;
