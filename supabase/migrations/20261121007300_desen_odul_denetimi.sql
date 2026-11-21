-- Profil deseni ve sunucunun verdiği ödül (21 Kasım güvenlik taraması, Halka oturumu bilgisiyle).
-- 1) ortak.profil_ayari: p_desen yalnız '' (varsayılan) ya da oyuncunun kazandığı bir ödül kimliği olabilir:
--    ortak.oduller'de (oyun, kullanıcı, odul = p_desen) satırı ya da ortak.oyuncular.baglama_odulu = p_desen.
--    Henüz çıkmamış ya da kazanılmamış desen seçilemez ('desen_yok').
-- 2) ortak.odul_kaydet: oyunun hesap bağlama ödülü (oyunlar.ayarlar.hesap.baglama_odulu) yalnız sunucu verdiyse
--    (oyuncular.baglama_odulu aynı) kaydedilir; değilse sessizce atlanır (istemci eşitlemesi bozulmasın).
-- Kalan risk: sezon ve etkinlik ödülleri istemcide hesaplanıp odul_kaydet ile yazılıyor; tam kapanış için sunucu
-- doğrulaması gerekir (ISTEKLER). Ödüller yalnız görünüş; puan, sıralama ve ödemeye etkisi yok.

create or replace function ortak.profil_ayari(p_oyun text, p_gizli boolean default null, p_desen text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); o ortak.oyuncular;
begin
  if ortak.anonim() then raise exception 'misafir' using errcode = '42501'; end if;
  if not ortak.hiz_siniri('profil_ayari:' || u, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  if nullif(p_desen, '') is not null
     and not exists (select 1 from ortak.oduller d where d.oyun_id = p_oyun and d.kullanici_id = u and d.odul = p_desen)
     and not exists (select 1 from ortak.oyuncular y where y.oyun_id = p_oyun and y.kullanici_id = u and y.baglama_odulu = p_desen) then
    raise exception 'desen_yok' using errcode = '42501';
  end if;
  update ortak.oyuncular set
    profil_gizli = coalesce(p_gizli, profil_gizli),
    desen = case when p_desen is null then desen else nullif(p_desen, '') end
  where oyun_id = p_oyun and kullanici_id = u
  returning * into o;
  if not found then return null; end if;
  return jsonb_build_object('profil', o.profil_id, 'gizli', o.profil_gizli, 'desen', o.desen);
end $$;

create or replace function ortak.odul_kaydet(p_oyun text, p_oduller jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare u uuid := ortak.kim(); n integer; bag text; verildi text;
begin
  if ortak.anonim() then raise exception 'kalici_hesap_gerekli'; end if;
  if jsonb_typeof(p_oduller) <> 'array' or jsonb_array_length(p_oduller) > 100 then
    raise exception 'oduller_gecersiz';
  end if;
  if exists (select 1 from jsonb_array_elements(p_oduller) x where x ->> 'odul' like 'sira:%') then
    raise exception 'odul_yasak';
  end if;
  if not ortak.hiz_siniri('odul:' || u, 30, 60) then raise exception 'cok_istek' using errcode = '54000'; end if;
  if (select count(*) from ortak.oduller where oyun_id = p_oyun and kullanici_id = u)
     + jsonb_array_length(p_oduller) > 1000 then
    raise exception 'odul_tavan' using errcode = '54000';
  end if;
  select ayarlar -> 'hesap' ->> 'baglama_odulu' into bag from ortak.oyunlar where id = p_oyun;
  select baglama_odulu into verildi from ortak.oyuncular where oyun_id = p_oyun and kullanici_id = u;
  insert into ortak.oduller (oyun_id, kullanici_id, odul, kaynak, kazanildi)
    select p_oyun, u, x ->> 'odul', x ->> 'kaynak',
           least(coalesce((x ->> 'kazanildi')::timestamptz, now()), now())
    from jsonb_array_elements(p_oduller) x
    where bag is null or x ->> 'odul' is distinct from bag or verildi is not distinct from bag
    on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
