-- Kurulum başına günde bir hesap günlük sıralamaya girer (kurucu, 15 Kasım 2026): bulmacayı bir hesapta çözüp
-- çözümü öbür hesapta hızla girerek üste çıkmayı zorlaştırır. Kurulum kimliği istemcinin rastgele ürettiği ve depoda
-- tuttuğu kimliktir (siralama paketi `cihaz`); aynı telefondaki uygulama ve tarayıcı ayrı sayılır, parmak izi yok.
-- Sunucuda yalnız özeti (SHA-256) tutulur, 3 gün sonra silinir. Kimlik verilmezse (eski istemci) denetim yapılmaz.
-- Satırda kullanıcı kimliği yabancı anahtarsız tutulur: hesap silinince satır kalır, böylece silip yeniden açan aynı
-- gün aynı kurulumdan da giremez.

create table ortak.kurulum_gunluk (
  oyun_id text not null references ortak.oyunlar (id) on delete cascade,
  kurulum_ozeti bytea not null,
  donem text not null,
  kullanici_id uuid not null,
  olusturma timestamptz not null default now(),
  primary key (oyun_id, kurulum_ozeti, donem)
);
alter table ortak.kurulum_gunluk enable row level security;

-- Bu kurulum bu dönemde başka bir hesaba ait mi? Değilse bu hesap adına ayırır. true = başka hesap (skor yazılmaz).
create function ortak.kurulum_baska_hesap(p_oyun text, p_cihaz text, p_donem text, p_kullanici uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare o bytea; sahip uuid;
begin
  if p_cihaz is null then return false; end if;
  o := sha256(convert_to(p_cihaz, 'UTF8'));
  insert into ortak.kurulum_gunluk (oyun_id, kurulum_ozeti, donem, kullanici_id)
    values (p_oyun, o, p_donem, p_kullanici) on conflict do nothing;
  select kullanici_id into sahip from ortak.kurulum_gunluk where oyun_id = p_oyun and kurulum_ozeti = o and donem = p_donem;
  if random() < 0.01 then delete from ortak.kurulum_gunluk where olusturma < now() - interval '3 days'; end if;
  return sahip is distinct from p_kullanici;
end $$;

-- skor_yaz: p_cihaz eklendi (imza değiştiği için yeniden oluşturulur). Dönüş durumuna 'cihaz' eklendi.
drop function ortak.skor_yaz(text, uuid, text, text, numeric, uuid, numeric, numeric, jsonb, text[], integer);
create function ortak.skor_yaz(
  p_oyun text, p_kullanici uuid, p_tur text, p_donem text, p_puan numeric, p_run_id uuid,
  p_ikincil numeric default null, p_lig_puani numeric default null, p_ayrinti jsonb default null,
  p_bayraklar text[] default '{}', p_seviye_puani integer default null, p_cihaz text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id bigint; hafta date;
begin
  select id into v_id from ortak.skorlar where run_id = p_run_id;
  if v_id is not null then return jsonb_build_object('durum', 'tekrar', 'id', v_id); end if;

  insert into ortak.oyuncular (oyun_id, kullanici_id) values (p_oyun, p_kullanici)
    on conflict (oyun_id, kullanici_id) do update set son_gorulme = now();
  if p_seviye_puani is not null then
    update ortak.oyuncular set seviye_puani = p_seviye_puani where oyun_id = p_oyun and kullanici_id = p_kullanici;
  end if;

  if p_tur = 'gunluk' and ortak.kurulum_baska_hesap(p_oyun, p_cihaz, p_donem, p_kullanici) then
    return jsonb_build_object('durum', 'cihaz');
  end if;

  insert into ortak.skorlar (oyun_id, kullanici_id, tur, donem, puan, ikincil, lig_puani, run_id, ayrinti, bayraklar)
  values (p_oyun, p_kullanici, p_tur, p_donem, p_puan, p_ikincil, p_lig_puani, p_run_id, p_ayrinti, p_bayraklar)
  on conflict (oyun_id, tur, donem, kullanici_id) do nothing
  returning id into v_id;
  if v_id is null then return jsonb_build_object('durum', 'prova'); end if;

  if p_tur = 'gunluk' and p_lig_puani is not null
     and exists (select 1 from ortak.oyunlar where id = p_oyun and ayarlar ? 'lig') then
    hafta := ortak.iso_hafta(p_donem::date);
    perform ortak.lig_ata(p_oyun, p_kullanici, hafta);
    perform ortak.lig_puani_guncelle(p_oyun, p_kullanici, hafta);
  end if;
  return jsonb_build_object('durum', 'yeni', 'id', v_id);
end $$;

-- gun_toplami_yaz (Beat Greedy): p_cihaz eklendi; başka hesaba ait kurulumda satır açılmaz, 'durum': 'cihaz' döner.
drop function ortak.gun_toplami_yaz(text, uuid, text, numeric, numeric);
create function ortak.gun_toplami_yaz(p_oyun text, p_kullanici uuid, p_gun text, p_toplam numeric,
  p_ikincil numeric default null, p_cihaz text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_hafta date; v_puan numeric;
begin
  if p_gun !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'gun_gecersiz'; end if;
  if p_toplam < 0 then raise exception 'toplam_gecersiz'; end if;
  insert into ortak.oyuncular (oyun_id, kullanici_id) values (p_oyun, p_kullanici)
    on conflict (oyun_id, kullanici_id) do update set son_gorulme = now();
  if ortak.kurulum_baska_hesap(p_oyun, p_cihaz, p_gun, p_kullanici) then
    return jsonb_build_object('gun', p_gun, 'durum', 'cihaz');
  end if;
  insert into ortak.skorlar (oyun_id, kullanici_id, tur, donem, puan, ikincil, lig_puani, run_id)
    values (p_oyun, p_kullanici, 'gunluk', p_gun, p_toplam, p_ikincil, p_toplam, gen_random_uuid())
    on conflict (oyun_id, tur, donem, kullanici_id) do update
      set puan = excluded.puan, ikincil = excluded.ikincil, lig_puani = excluded.lig_puani;
  if exists (select 1 from ortak.oyunlar where id = p_oyun and ayarlar ? 'lig') then
    v_hafta := ortak.iso_hafta(p_gun::date);
    perform ortak.lig_ata(p_oyun, p_kullanici, v_hafta);
    perform ortak.lig_puani_guncelle(p_oyun, p_kullanici, v_hafta);
    select puan into v_puan from ortak.lig_uyeleri where oyun_id = p_oyun and hafta = v_hafta and kullanici_id = p_kullanici;
  end if;
  return jsonb_build_object('gun', p_gun, 'toplam', p_toplam, 'hafta_puani', v_puan);
end $$;

revoke execute on function
  ortak.skor_yaz(text, uuid, text, text, numeric, uuid, numeric, numeric, jsonb, text[], integer, text),
  ortak.gun_toplami_yaz(text, uuid, text, numeric, numeric, text),
  ortak.kurulum_baska_hesap(text, text, text, uuid)
from public, anon, authenticated;

-- Silmede kurulum satırlarındaki kullanıcı kimliği anonim değere çevrilir: iz kalmaz, kurulum o gün başka hesaba
-- (silip yeniden açılan dahil) kapalı kalır.
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
