-- Silinen hesabın ad kilidi (Halka AD-1, kurucu 17 Kasım 2026: "kullanamasın, zor değilse"). Oyun hesabını silip
-- yeniden açan, adını değiştirdikten sonraki 30 günlük kilidi atlatıyordu. Silmede kilit sürüyorsa ad ve son değiştirme
-- zamanı, kişinin giriş kimliklerinin özetiyle (ortak.kimlik_ozetleri, 20261120001200) kilit bitene dek saklanır. Aynı
-- kişi o oyunda yeniden oyuncu satırı açınca ad geri gelir (ad_otomatik false, ad_degisti eskisi): kilit sürer, oyuncu
-- ad seçme adımına takılmadan oynar. Kilit sürerken ad başkasına verilmez. Kilidi bitmiş satır silmelerde atılır.
-- Misafirin giriş kimliği olmadığı için misafir etkilenmez.

create table ortak.silinen_adlar (
  oyun_id text not null references ortak.oyunlar (id) on delete cascade,
  ozet bytea not null,
  ad text not null,
  ad_anahtari text not null,
  ad_degisti timestamptz not null,
  bitis timestamptz not null,
  primary key (oyun_id, ozet)
);
create index silinen_adlar_ad on ortak.silinen_adlar (oyun_id, ad_anahtari);
alter table ortak.silinen_adlar enable row level security;
-- Politika yok: istemci erişemez.

-- Yeni oyuncu satırında saklı ad geri gelir. Satır zaten varsa (on conflict) dokunulmaz; seçilmiş adla gelen satır
-- (Beat Greedy profil eşlemesi) olduğu gibi kalır. Önce ucuz denetim: o oyunda süren saklı ad yoksa özet hesaplanmaz.
create function ortak.silinen_ad_geri() returns trigger
language plpgsql security definer set search_path = '' as $$
declare s ortak.silinen_adlar;
begin
  if new.ad is not null and not new.ad_otomatik then return new; end if;
  if not exists (select 1 from ortak.silinen_adlar where oyun_id = new.oyun_id and bitis > now()) then return new; end if;
  if exists (select 1 from ortak.oyuncular where oyun_id = new.oyun_id and kullanici_id = new.kullanici_id) then return new; end if;
  select * into s from ortak.silinen_adlar
    where oyun_id = new.oyun_id and bitis > now() and ozet = any (ortak.kimlik_ozetleri(new.kullanici_id))
    order by ad_degisti desc limit 1;
  if not found then return new; end if;
  delete from ortak.silinen_adlar where oyun_id = new.oyun_id and ad_anahtari = s.ad_anahtari;
  if exists (select 1 from ortak.oyuncular where oyun_id = new.oyun_id and ad_anahtari = s.ad_anahtari) then return new; end if;
  new.ad := s.ad;
  new.ad_anahtari := s.ad_anahtari;
  new.ad_otomatik := false;
  new.ad_degisti := s.ad_degisti;
  return new;
end $$;
create trigger silinen_ad_geri before insert on ortak.oyuncular
  for each row execute function ortak.silinen_ad_geri();

-- Silme: 20261120001500 sürümü + kilit sürüyorsa adı sakla, kilidi bitmişleri at.
create or replace function ortak.oyun_verisini_sil(p_oyun text) returns void
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); fn text; gun int;
begin
  select ayarlar -> 'hesap' ->> 'silme_fonksiyonu', coalesce((ayarlar -> 'ad' ->> 'degistirme_gun')::int, 30)
    into fn, gun from ortak.oyunlar where id = p_oyun;
  if not found then raise exception 'oyun_yok'; end if;
  insert into ortak.silinen_adlar (oyun_id, ozet, ad, ad_anahtari, ad_degisti, bitis)
    select p_oyun, z, o.ad, o.ad_anahtari, o.ad_degisti, o.ad_degisti + make_interval(days => gun)
    from ortak.oyuncular o, unnest(ortak.kimlik_ozetleri(u)) z
    where o.oyun_id = p_oyun and o.kullanici_id = u and o.ad is not null and not o.ad_otomatik
      and o.ad_degisti + make_interval(days => gun) > now()
    on conflict (oyun_id, ozet) do update
      set ad = excluded.ad, ad_anahtari = excluded.ad_anahtari, ad_degisti = excluded.ad_degisti, bitis = excluded.bitis;
  delete from ortak.silinen_adlar where bitis <= now();
  perform ortak.oyun_verisini_sil_ek(p_oyun, u);
  delete from ortak.kayitlar where oyun_id = p_oyun and kullanici_id = u;
  delete from ortak.oyuncular where oyun_id = p_oyun and kullanici_id = u;
  if fn is not null then
    if to_regprocedure(fn || '(uuid)') is null then raise exception 'silme_fonksiyonu_yok: %', fn; end if;
    execute format('select %s($1)', to_regprocedure(fn || '(uuid)')::regproc) using u;
  end if;
  update ortak.kurulum_gunluk set kullanici_id = '00000000-0000-0000-0000-000000000000'
    where oyun_id = p_oyun and kullanici_id = u;
  insert into ortak.silinen_kimlikler (oyun_id, ozet)
    select p_oyun, o from unnest(ortak.kimlik_ozetleri(u)) o
    on conflict (oyun_id, ozet) do update set silindi = now();
  delete from ortak.silinen_kimlikler where silindi < now() - interval '2 days';
  if not ortak.kalan_veri_var(u) then
    delete from auth.users where id = u;
  end if;
end $$;

-- Ad değiştirme: 20261120000300 sürümü + saklı ad kilit sürerken başkasına verilmez ('alinmis').
create or replace function ortak.ad_degistir(p_oyun text, p_ad text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := ortak.kim();
  a jsonb;
  v_ad text := btrim(p_ad);
  o ortak.oyuncular;
  gun int;
begin
  if ortak.anonim() then raise exception 'kalici_hesap_gerekli'; end if;
  select coalesce(ayarlar -> 'ad', '{}') into a from ortak.oyunlar where id = p_oyun;
  if not found then raise exception 'oyun_yok'; end if;
  if not ortak.ad_bicimi(v_ad, coalesce((a ->> 'en_az')::int, 3), coalesce((a ->> 'en_cok')::int, 16)) then
    return jsonb_build_object('durum', 'bicim');
  end if;
  if not ortak.ad_uygun(v_ad, coalesce(array(select jsonb_array_elements_text(a -> 'yasakli')), '{}'))
     or exists (select 1 from ortak.engelli_adlar where oyun_id = p_oyun and ad_anahtari = ortak.ad_anahtari(v_ad)) then
    return jsonb_build_object('durum', 'uygunsuz');
  end if;

  insert into ortak.oyuncular (oyun_id, kullanici_id) values (p_oyun, u) on conflict do nothing;
  select * into o from ortak.oyuncular where oyun_id = p_oyun and kullanici_id = u for update;

  gun := coalesce((a ->> 'degistirme_gun')::int, 30);
  if o.ad_degisti is not null and o.ad_degisti > now() - make_interval(days => gun) then
    return jsonb_build_object('durum', 'bekle',
      'bekle_gun', ceil(extract(epoch from (o.ad_degisti + make_interval(days => gun) - now())) / 86400));
  end if;

  if exists (select 1 from ortak.silinen_adlar
             where oyun_id = p_oyun and ad_anahtari = ortak.ad_anahtari(v_ad) and bitis > now()) then
    return jsonb_build_object('durum', 'alinmis');
  end if;

  begin
    update ortak.oyuncular set ad = v_ad, ad_anahtari = ortak.ad_anahtari(v_ad), ad_otomatik = false, ad_degisti = now()
    where oyun_id = p_oyun and kullanici_id = u;
  exception when unique_violation then
    return jsonb_build_object('durum', 'alinmis');
  end;
  return jsonb_build_object('durum', 'ok', 'ad', v_ad);
end $$;

revoke execute on function ortak.silinen_ad_geri() from public, anon, authenticated;
