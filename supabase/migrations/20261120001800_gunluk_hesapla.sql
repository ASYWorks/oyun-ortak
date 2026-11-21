-- Günlük oyun, lig ve etkinlik yalnız hesapla (kurucu, 15 Kasım 2026): seviyeler ve arşiv hesapsız oynanır; sıralama
-- günlükten, ligden ve etkinlikten geldiği için misafir (anonim oturum) sıralamaya hiç girmez. skor_yaz ve
-- gun_toplami_yaz misafirde skor yazmaz, `durum: 'misafir'` döner (oyun girişe yönlendirir). Var olan misafir
-- skorları ve lig üyelikleri silinir (yayın öncesi). Hesap devri (hesap_devral) artık taşıyacak misafir skoru bulmaz.

create or replace function ortak.skor_yaz(
  p_oyun text, p_kullanici uuid, p_tur text, p_donem text, p_puan numeric, p_run_id uuid,
  p_ikincil numeric default null, p_lig_puani numeric default null, p_ayrinti jsonb default null,
  p_bayraklar text[] default '{}', p_seviye_puani integer default null, p_cihaz text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id bigint; hafta date;
begin
  select id into v_id from ortak.skorlar where run_id = p_run_id;
  if v_id is not null then return jsonb_build_object('durum', 'tekrar', 'id', v_id); end if;
  if exists (select 1 from auth.users where id = p_kullanici and is_anonymous) then
    return jsonb_build_object('durum', 'misafir');
  end if;

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

create or replace function ortak.gun_toplami_yaz(p_oyun text, p_kullanici uuid, p_gun text, p_toplam numeric,
  p_ikincil numeric default null, p_cihaz text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_hafta date; v_puan numeric;
begin
  if p_gun !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'gun_gecersiz'; end if;
  if p_toplam < 0 then raise exception 'toplam_gecersiz'; end if;
  if exists (select 1 from auth.users where id = p_kullanici and is_anonymous) then
    return jsonb_build_object('gun', p_gun, 'durum', 'misafir');
  end if;
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

delete from ortak.skorlar s using auth.users u where u.id = s.kullanici_id and u.is_anonymous;
delete from ortak.lig_uyeleri l using auth.users u where u.id = l.kullanici_id and u.is_anonymous;
