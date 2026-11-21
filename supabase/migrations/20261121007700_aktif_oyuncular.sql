-- Göç 7700: operatör paneli için oyun başına aktif oyuncu sayıları.
-- ortak.aktif_oyuncular: oyuncunun sunucuya dokunduğu her İstanbul günü için tek satır (oyun, gün, kullanıcı) ve o günkü
-- son temas zamanı. Satırı tetikleyiciler yazar; oyunların koduna dokunulmaz. Yalnız API isteğiyle (PostgREST/Edge Function/
-- Sticky sunucusu) gelen yazımlar sayılır: zamanlanmış işler, göçler ve başka oyuncunun isteğiyle değişen satırlar sayılmaz.
-- `son` en çok 5 dakikada bir güncellenir; "anlık" sayısı bu yüzden son 10 dakikadır.
-- Sunucuya hiç dokunmadan çevrimdışı oynayan misafir sayılmaz (bilinçli; ölçüm PostHog'da).
-- Hesap silinince iz kalmaz: tam silmede auth.users bağı, tek oyun silmede ortak.oyuncular satırının silinmesi temizler.

create table ortak.aktif_oyuncular (
  oyun_id text not null,
  gun date not null,
  kullanici_id uuid not null references auth.users on delete cascade,
  son timestamptz not null default now(),
  primary key (oyun_id, gun, kullanici_id)
);
alter table ortak.aktif_oyuncular enable row level security;  -- politika yok: istemciye kapalı
revoke all on ortak.aktif_oyuncular from anon, authenticated;

create function ortak.aktif_isaretle(p_oyun text, p_kullanici uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  c jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
begin
  if c is null or p_kullanici is null then return; end if;                      -- API dışı (cron, göç)
  if c->>'role' = 'authenticated' and (c->>'sub')::uuid is distinct from p_kullanici then return; end if;
  if c->>'role' not in ('authenticated', 'service_role') then return; end if;
  insert into ortak.aktif_oyuncular as a (oyun_id, gun, kullanici_id) values (p_oyun, ortak.bugun(), p_kullanici)
    on conflict (oyun_id, gun, kullanici_id) do update set son = now() where a.son < now() - interval '5 minutes';
exception when others then null;  -- sayım oyunun yazımını asla bozmaz
end $$;
revoke all on function ortak.aktif_isaretle(text, uuid) from public, anon, authenticated;

-- ortak tabloları: oyun_id + kullanici_id
create function ortak.aktif_tetik_ortak() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform ortak.aktif_isaretle(new.oyun_id, new.kullanici_id);
  return null;
end $$;
-- oyun şemaları: user_id, oyun kimliği tetikleyici argümanı
create function ortak.aktif_tetik_oyun() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform ortak.aktif_isaretle(tg_argv[0], new.user_id);
  return null;
end $$;
revoke all on function ortak.aktif_tetik_ortak(), ortak.aktif_tetik_oyun() from public, anon, authenticated;

create trigger aktif after insert or update on ortak.kayitlar for each row execute function ortak.aktif_tetik_ortak();
create trigger aktif after insert or update on ortak.skorlar for each row execute function ortak.aktif_tetik_ortak();
create trigger aktif after insert or update on ortak.denemeler for each row execute function ortak.aktif_tetik_ortak();
create trigger aktif after insert or update on sezgi.attempts for each row execute function ortak.aktif_tetik_oyun('sezgi');
create trigger aktif after insert or update on sezgi.level_progress for each row execute function ortak.aktif_tetik_oyun('sezgi');
create trigger aktif after insert or update on sticky.stats for each row execute function ortak.aktif_tetik_oyun('sticky');

-- ponytail: her çağrıda 365 günlük distinct sayım; oyuncu sayısı yüz binleri bulursa günlük özet tablosuna geç
create function ortak.aktif_oyuncu_ozeti() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'oyun', o.id, 'ad', o.ad,
    'anlik', (select count(distinct a.kullanici_id) from ortak.aktif_oyuncular a
              where a.oyun_id = o.id and a.gun >= ortak.bugun() - 1 and a.son > now() - interval '10 minutes'),
    'gun',  (select count(*) from ortak.aktif_oyuncular a where a.oyun_id = o.id and a.gun = ortak.bugun()),
    'hafta', (select count(distinct a.kullanici_id) from ortak.aktif_oyuncular a where a.oyun_id = o.id and a.gun > ortak.bugun() - 7),
    'ay',   (select count(distinct a.kullanici_id) from ortak.aktif_oyuncular a where a.oyun_id = o.id and a.gun > ortak.bugun() - 30),
    'yil',  (select count(distinct a.kullanici_id) from ortak.aktif_oyuncular a where a.oyun_id = o.id and a.gun > ortak.bugun() - 365),
    'ilk_gun', (select min(a.gun) from ortak.aktif_oyuncular a where a.oyun_id = o.id),
    'seri', (select jsonb_agg(jsonb_build_object('gun', g.gun, 'n',
               (select count(*) from ortak.aktif_oyuncular a where a.oyun_id = o.id and a.gun = g.gun)) order by g.gun)
             from (select (ortak.bugun() - i) as gun from generate_series(29, 0, -1) i) g)
  ) order by o.ad), '[]'::jsonb)
  from ortak.oyunlar o
$$;
revoke all on function ortak.aktif_oyuncu_ozeti() from public, anon, authenticated;

create or replace function ortak.panel_durumu(p_anahtar text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not ortak.panel_hiz() then raise exception 'cok_istek' using errcode = '54000'; end if;
  if not ortak.panel_anahtar_dogru(p_anahtar) then return null; end if;
  return ortak.isletim_durumu() || jsonb_build_object(
    'son_yedek', (select jsonb_build_object('zaman', y.zaman, 'basarili', y.basarili, 'boyut_bayt', y.boyut_bayt)
                  from ortak.yedek_kayitlari y where y.proje = 'canli' order by y.zaman desc limit 1),
    'auth_kullanici', (select count(*) from auth.users),
    -- Supabase'in aylık aktif kullanıcı (MAU) kotasına yakın ölçü: son 30 günde oturumu yenilenen hesap
    'aylik_aktif_hesap', (select count(distinct r.user_id) from auth.refresh_tokens r where r.updated_at > now() - interval '30 days'),
    'oyuncular', ortak.aktif_oyuncu_ozeti());
end $$;

select cron.schedule('ortak-aktif-oyuncu-temizle', '50 3 * * *', $$delete from ortak.aktif_oyuncular where gun < ortak.bugun() - 400$$);

-- tek oyun silme (ortak.oyun_verisini_sil) oyuncu satırını siler; o oyunun etkinlik satırları da gider
create function ortak.aktif_sil() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from ortak.aktif_oyuncular where oyun_id = old.oyun_id and kullanici_id = old.kullanici_id;
  return null;
end $$;
revoke all on function ortak.aktif_sil() from public, anon, authenticated;
create trigger aktif_sil after delete on ortak.oyuncular for each row execute function ortak.aktif_sil();
