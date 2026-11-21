-- Aynı gün silip yeniden açanı o günün sıralamasına almama (kurucu, 15 Kasım 2026). Hesap oyun oyun ayrı olduğundan
-- (20261120001100) kişi tek oynadığı oyunu silince giriş kaydı da gider; aynı e-postayla yeniden girince yeni kimlik
-- alır ve günün bulmacasını yeniden oynayıp sıralamaya girebilirdi. Hesabı yeniden açmak serbesttir; yalnız o gün o
-- oyunun günlük sıralamasına (ortak.skorlar, tur 'gunluk') skor yazılmaz. Silmede e-postanın ve Google/Apple
-- kimliğinin tek yönlü özeti (SHA-256) o oyun için saklanır, 2 gün sonra silinir. Misafirin (anonim) e-postası ya da
-- kimliği olmadığı için misafir etkilenmez.

create table ortak.silinen_kimlikler (
  oyun_id text not null references ortak.oyunlar (id) on delete cascade,
  ozet bytea not null,
  silindi timestamptz not null default now(),
  primary key (oyun_id, ozet)
);
create index silinen_kimlikler_zaman on ortak.silinen_kimlikler (oyun_id, silindi);
alter table ortak.silinen_kimlikler enable row level security;
-- Politika yok: istemci erişemez.

-- Kişinin giriş kimliklerinin özetleri: e-posta (küçük harf) ve e-posta dışı sağlayıcı kimlikleri (Google, Apple).
create function ortak.kimlik_ozetleri(u uuid) returns bytea[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct sha256(convert_to(x, 'UTF8'))), '{}')
  from (
    select 'eposta:' || lower(email) as x from auth.users where id = u and coalesce(email, '') <> ''
    union all
    select 'kimlik:' || provider || ':' || provider_id from auth.identities where user_id = u and provider <> 'email'
  ) t
$$;

-- Bu kişi bu oyundaki hesabını bugün (İstanbul) mü sildi? Önce ucuz denetim: o oyunda bugün silme yoksa hiç özet
-- hesaplanmaz (oyuncu satırı eklemeleri sık).
create function ortak.bugun_silindi(p_oyun text, u uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare bas timestamptz := date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
begin
  if not exists (select 1 from ortak.silinen_kimlikler where oyun_id = p_oyun and silindi >= bas) then return false; end if;
  return exists (select 1 from ortak.silinen_kimlikler
                 where oyun_id = p_oyun and silindi >= bas and ozet = any (ortak.kimlik_ozetleri(u)));
end $$;

-- Günlük skor yazılmaz: skor_yaz 'prova' döner (sayılmayan gönderim), gun_toplami_yaz satır açmaz.
create function ortak.ayni_gun_siralama_engeli() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.tur = 'gunluk' and ortak.bugun_silindi(new.oyun_id, new.kullanici_id) then return null; end if;
  return new;
end $$;
create trigger ayni_gun_siralama_engeli before insert on ortak.skorlar
  for each row execute function ortak.ayni_gun_siralama_engeli();

-- Silmede özetler yazılır (giriş kaydı silinmeden önce); 2 günden eski özetler atılır.
create or replace function ortak.oyun_verisini_sil(p_oyun text) returns void
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); fn text;
begin
  select ayarlar -> 'hesap' ->> 'silme_fonksiyonu' into fn from ortak.oyunlar where id = p_oyun;
  if not found then raise exception 'oyun_yok'; end if;
  perform ortak.oyun_verisini_sil_ek(p_oyun, u);
  delete from ortak.kayitlar where oyun_id = p_oyun and kullanici_id = u;
  delete from ortak.oyuncular where oyun_id = p_oyun and kullanici_id = u;
  if fn is not null then
    if to_regprocedure(fn || '(uuid)') is null then raise exception 'silme_fonksiyonu_yok: %', fn; end if;
    execute format('select %s($1)', to_regprocedure(fn || '(uuid)')::regproc) using u;
  end if;
  insert into ortak.silinen_kimlikler (oyun_id, ozet)
    select p_oyun, o from unnest(ortak.kimlik_ozetleri(u)) o
    on conflict (oyun_id, ozet) do update set silindi = now();
  delete from ortak.silinen_kimlikler where silindi < now() - interval '2 days';
  if not ortak.kalan_veri_var(u) then
    delete from auth.users where id = u;
  end if;
end $$;

revoke execute on function ortak.kimlik_ozetleri(uuid), ortak.bugun_silindi(text, uuid), ortak.ayni_gun_siralama_engeli()
  from public, anon, authenticated;
