-- Bildirim konuları ve günde bir sınırı (Sticky Ten isteği; kurucu 16 Kasım 2026, ORTAK_MODUL bildirim kuralları).
-- 1) Anahtar satırında oyuncunun açtığı konular (ör. 'takip', 'bekleyen'). İstemci bildirim_anahtari_yaz'a p_konular
--    verir; null verirse var olan konular korunur. Sunucu servis rolüyle konuya göre okur (konular @> '{bekleyen}').
-- 2) ortak.bildirim_hakki_al: konu başına alıcı başına günde bir hak, sunucu yeniden başlasa da korunur. Verilen
--    listeden o gün bu konuda hakkı olanları döndürür ve hakkı düşer (aynı anda gelen iki çağrı aynı kişiyi iki kez
--    almaz). Kayıt 3 gün tutulur. Yalnız servis rolü.

alter table ortak.bildirim_anahtarlari add column if not exists konular text[] not null default '{}';

drop function ortak.bildirim_anahtari_yaz(text, text, text, text);
create function ortak.bildirim_anahtari_yaz(p_oyun text, p_platform text, p_anahtar text, p_dil text default 'tr',
                                            p_konular text[] default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim();
begin
  if ortak.anonim() then raise exception 'kalici_hesap_gerekli'; end if;
  if not ortak.hiz_siniri('bildirim:' || u, 20, 3600) then raise exception 'cok_istek' using errcode = '54000'; end if;
  if p_konular is not null and (cardinality(p_konular) > 10
      or exists (select 1 from unnest(p_konular) k where k !~ '^[a-z_]{1,20}$')) then
    raise exception 'konu_gecersiz';
  end if;
  insert into ortak.bildirim_anahtarlari as b (oyun_id, anahtar, kullanici_id, platform, dil, son_gorulme, konular)
    values (p_oyun, p_anahtar, u, p_platform, coalesce(p_dil, 'tr'), now(), coalesce(p_konular, '{}'))
    on conflict (oyun_id, anahtar) do update
      set kullanici_id = excluded.kullanici_id, platform = excluded.platform, dil = excluded.dil, son_gorulme = now(),
          konular = case when p_konular is null and b.kullanici_id = excluded.kullanici_id then b.konular
                         else coalesce(p_konular, '{}') end;
  delete from ortak.bildirim_anahtarlari b
    where b.oyun_id = p_oyun and b.kullanici_id = u
      and b.anahtar not in (select x.anahtar from ortak.bildirim_anahtarlari x
                            where x.oyun_id = p_oyun and x.kullanici_id = u
                            order by x.son_gorulme desc limit 10);
end $$;
revoke execute on function ortak.bildirim_anahtari_yaz(text, text, text, text, text[]) from public, anon;
grant execute on function ortak.bildirim_anahtari_yaz(text, text, text, text, text[]) to authenticated;

create table ortak.bildirim_gonderimleri (
  oyun_id text not null references ortak.oyunlar (id) on delete cascade,
  kullanici_id uuid not null references auth.users (id) on delete cascade,
  konu text not null,
  gun date not null,
  primary key (oyun_id, kullanici_id, konu, gun)
);
alter table ortak.bildirim_gonderimleri enable row level security;
revoke all on ortak.bildirim_gonderimleri from public, anon, authenticated;

-- Gün İstanbul takvimiyle. Dönüş: hakkı olan (bu çağrıda hakkı düşülen) kullanıcılar.
create function ortak.bildirim_hakki_al(p_oyun text, p_konu text, p_kullanicilar uuid[]) returns uuid[]
language plpgsql security definer set search_path = '' as $$
declare bugun date := (now() at time zone 'Europe/Istanbul')::date; r uuid[];
begin
  delete from ortak.bildirim_gonderimleri where gun < bugun - 2;
  with y as (
    insert into ortak.bildirim_gonderimleri (oyun_id, kullanici_id, konu, gun)
    select p_oyun, k, p_konu, bugun from unnest(p_kullanicilar) k
    on conflict do nothing
    returning kullanici_id
  )
  select coalesce(array_agg(kullanici_id), '{}') into r from y;
  return r;
end $$;
revoke execute on function ortak.bildirim_hakki_al(text, text, uuid[]) from public, anon, authenticated;
grant execute on function ortak.bildirim_hakki_al(text, text, uuid[]) to service_role;

-- "Bu oyundan sil" gönderim kayıtlarını da siler.
create or replace function ortak.oyun_verisini_sil_ek(p_oyun text, u uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from ortak.skorlar where oyun_id = p_oyun and kullanici_id = u;
  delete from ortak.denemeler where oyun_id = p_oyun and kullanici_id = u;
  delete from ortak.lig_uyeleri where oyun_id = p_oyun and kullanici_id = u;
  delete from ortak.oduller where oyun_id = p_oyun and kullanici_id = u;
  delete from ortak.haklar where oyun_id = p_oyun and kullanici_id = u;
  delete from ortak.sikayetler where oyun_id = p_oyun and (sikayet_eden = u or hedef = u);
  delete from ortak.bildirim_anahtarlari where oyun_id = p_oyun and kullanici_id = u;
  delete from ortak.bildirim_gonderimleri where oyun_id = p_oyun and kullanici_id = u;
end $$;
