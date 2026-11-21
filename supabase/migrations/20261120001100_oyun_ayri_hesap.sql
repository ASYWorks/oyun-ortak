-- Oyun oyun ayrı hesap ve misafir adı (kurucu, 15 Kasım 2026).
--
-- 1) Hesaplar oyuncunun gözünde oyun oyun ayrıdır: giriş sistemi (auth.users) teknik olarak tek kalır, ama silme
--    yalnız o oyunu kapsar. `oyun_verisini_sil` o oyunun verisini siler; kişinin başka hiçbir oyunda verisi
--    kalmamışsa giriş kaydını (auth.users: e-posta, Google/Apple kimliği) da siler. "Tamamen sil" (`hesabi_sil`) ve
--    oyun listesi (`hesap_ozeti`) oyunlar geçene kadar açık kalır; sonraki göçte kapanır (ISTEKLER: OA-1).
-- 2) Otomatik ad (misafir ve adı olmayan hesap): `#` + 7 karakter, ör. #K7P2X9M. Karışan karakter (O/0, I/1) yok.
--    Elle seçilen adlarda `#` kullanılamaz (ad_bicimi), bu yüzden otomatik ad seçilmiş bir adla karıştırılmaz.
--    Var olan otomatik adlar (ör. "Oyuncu4821") yeni biçime çevrilir. Oyunun ad.onekler ayarı artık kullanılmaz.

create function ortak.misafir_kodu() returns text
language sql volatile set search_path = '' as $$
  select '#' || string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '')
  from generate_series(1, 7)
$$;
revoke execute on function ortak.misafir_kodu() from public, anon, authenticated;

create or replace function ortak.otomatik_ad(p_oyun text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := ortak.kim();
  o ortak.oyuncular;
  v_ad text;
begin
  perform 1 from ortak.oyunlar where id = p_oyun;
  if not found then raise exception 'oyun_yok'; end if;
  insert into ortak.oyuncular (oyun_id, kullanici_id) values (p_oyun, u) on conflict do nothing;
  select * into o from ortak.oyuncular where oyun_id = p_oyun and kullanici_id = u for update;
  if o.ad is not null then return jsonb_build_object('durum', 'ok', 'ad', o.ad); end if;
  for i in 1..10 loop
    v_ad := ortak.misafir_kodu();
    begin
      update ortak.oyuncular set ad = v_ad, ad_anahtari = ortak.ad_anahtari(v_ad), ad_otomatik = true
        where oyun_id = p_oyun and kullanici_id = u;
      return jsonb_build_object('durum', 'ok', 'ad', v_ad);
    exception when unique_violation then
      null;
    end;
  end loop;
  return jsonb_build_object('durum', 'alinmis');
end $$;

-- Var olan otomatik adlar yeni biçime (yayın öncesi; ad_degisti dokunulmaz, 30 gün hakkı harcanmaz).
do $$
declare r record; v text;
begin
  for r in select oyun_id, kullanici_id from ortak.oyuncular where ad_otomatik and ad is not null and left(ad, 1) <> '#' loop
    for i in 1..10 loop
      v := ortak.misafir_kodu();
      begin
        update ortak.oyuncular set ad = v, ad_anahtari = ortak.ad_anahtari(v)
          where oyun_id = r.oyun_id and kullanici_id = r.kullanici_id;
        exit;
      exception when unique_violation then null;
      end;
    end loop;
  end loop;
end $$;

-- Kişinin herhangi bir oyunda verisi kaldı mı? auth.users'a bağlı bütün tablolar taranır (yeni oyunun tabloları da
-- kendiliğinden girer); oyundan bağımsız kayıtlar sayılmaz: yaş beyanı, devir kodu, hız sayaçları.
create function ortak.kalan_veri_var(u uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare r record; var boolean;
begin
  for r in
    select c.conrelid::regclass as tablo, a.attname as sutun
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where c.contype = 'f' and c.confrelid = 'auth.users'::regclass and cardinality(c.conkey) = 1
      and n.nspname not in ('auth', 'storage', 'realtime', 'extensions', 'vault')
      and c.conrelid not in ('ortak.profiller'::regclass, 'ortak.devirler'::regclass, 'sezgi.rate_limits'::regclass)
  loop
    execute format('select exists (select 1 from %s where %I = $1)', r.tablo, r.sutun) into var using u;
    if var then return true; end if;
  end loop;
  return false;
end $$;
revoke execute on function ortak.kalan_veri_var(uuid) from public, anon, authenticated;

-- "Bu oyundaki hesabımı sil": o oyunun verisi; başka oyunda veri yoksa giriş kaydı da (zincirleme her şey).
-- İstemci ardından oturumu kapatır (hesap paketi `oyunVerisiniSil` bunu yapar).
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
  if not ortak.kalan_veri_var(u) then
    delete from auth.users where id = u;
  end if;
end $$;
