-- Nabız 30 sn (Halka isteği, 19 Kasım; kontrol kenara taşınınca nabız yeniden tek süre kaynağı). ipucu_ver son nabzı
-- 15 sn'den eski denemeyi duraklatılmış sayıyordu: 30 sn nabızda dürüst oyuncu ipucu alamazdı. Eşik 45 sn.
-- Süre kuralı (90 sn'ye kadar aralık tam, uzunu durak_ms) değişmedi: 30 sn nabızda iki kaçan nabız payı var.

create or replace function halka.ipucu_ver(p_anahtar text, p_halkalar jsonb, p_cevaplar text[], p_cozum jsonb, p_anlamlar jsonb,
                                p_kilit_sirasi integer[], p_kurallar jsonb, p_tur text, p_sira integer,
                                p_rot integer[], p_flip boolean[], p_kilitli integer[], p_tema text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  u uuid := auth.uid();
  d ortak.denemeler;
  sira int[];
  r int;
  sonuc jsonb;
  kelime text;
begin
  -- Cevabı açan ipuçları yalnız kalıcı hesaba (B2: misafir oturumlarıyla çözüm toplanmasın; günlük ve turnuva hesap ister, A17).
  if p_tur in ('anlam', 'kilit') and (u is null or ortak.anonim()) then
    raise exception 'hesap_gerekli' using errcode = '28000';
  end if;
  -- Duraklatılmış denemede ipucu yok: durdur nabzı geldiyse ya da nabızlı denemede son nabız 45 sn'den eskiyse (nabız 30 sn, bir gecikme payı).
  -- Nabızsız (eski istemci) denemede davranış aynı.
  if u is not null and exists (select 1 from ortak.denemeler e
      where e.oyun_id = 'halka' and e.kullanici_id = u and e.anahtar = p_anahtar and not e.bitti
        and (e.durdu or (e.son_nabiz is not null and e.son_nabiz < now() - interval '45 seconds'))) then
    raise exception 'duraklatildi' using errcode = 'P0001';
  end if;
  -- Hak (src/puan.ts IPUCU_HAK: anlam 2, kilit 2): bitince ipucu yok. Yanıtı kaybolan istek ya da iki cihaz fazladan
  -- ipucu biriktirip dogrula-halka'da 422 ipucu_hakki'na düşürmesin. Satır kilidi aynı anda gelen iki isteği sıraya koyar.
  if u is not null and p_tur in ('anlam', 'kilit') then
    perform 1 from ortak.denemeler where oyun_id = 'halka' and kullanici_id = u and anahtar = p_anahtar for update;
    if (select count(*) from ortak.denemeler e, jsonb_array_elements_text(coalesce(e.durum -> 'ipuclari', '[]')) x
        where e.oyun_id = 'halka' and e.kullanici_id = u and e.anahtar = p_anahtar and x = p_tur) >= 2 then
      return null;
    end if;
  end if;
  if p_tur = 'anlam' then
    -- Durum geldiyse p_sira oyuncunun yerleşimindeki dilim: çerçevede o dilimde okunan kelime. Yoksa asıl çözümün cevabı.
    if p_cozum is not null and (p_rot is not null or p_flip is not null) then
      if not halka.durum_gecerli(jsonb_array_length(p_halkalar), p_rot, p_flip) then
        raise exception 'gecersiz_durum' using errcode = '22023';
      end if;
      kelime := halka.dilim_oku(p_halkalar,
        halka.cerceve(p_halkalar, p_cozum, p_kurallar, halka.kilitliler(p_anahtar, p_kurallar, p_kilitli), p_rot, p_flip), p_sira);
    else
      kelime := p_cevaplar[p_sira + 1];
    end if;
    sonuc := case when p_anlamlar ->> kelime is not null then jsonb_build_object('anlam', p_anlamlar ->> kelime) end;
  elsif p_tur = 'kilit' then
    if p_cozum is null then return null; end if;
    if p_rot is not null or p_flip is not null then
      if not halka.durum_gecerli(jsonb_array_length(p_halkalar), p_rot, p_flip) then
        raise exception 'gecersiz_durum' using errcode = '22023';
      end if;
      sonuc := halka.kilit_sec(p_halkalar, p_cozum, p_kurallar, halka.kilitliler(p_anahtar, p_kurallar, p_kilitli),
        p_kilit_sirasi, p_rot, p_flip);
    else
      -- Durumsuz kilit (asıl çözümden sira. halka) kaldırıldı: istemci her zaman durum gönderir (B2).
      raise exception 'durum_gerekli' using errcode = '22023';
    end if;
  elsif p_tur = 'tema' then
    sonuc := jsonb_strip_nulls(jsonb_build_object('tema', p_tema));
  else
    raise exception 'gecersiz_tur' using errcode = '22023';
  end if;
  if sonuc is not null and u is not null then
    d := ortak.deneme_al('halka', u, p_anahtar);
    -- Tema ipucu bir kez sayılır: başlığı kaybeden istemci yeniden isteyebilir.
    if not (p_tur = 'tema' and coalesce(d.durum -> 'ipuclari', '[]'::jsonb) ? 'tema') then
      update ortak.denemeler
         set durum = durum || jsonb_build_object('ipuclari', coalesce(durum -> 'ipuclari', '[]'::jsonb) || to_jsonb(p_tur))
                   || case when p_tur = 'kilit' and not coalesce(durum -> 'kilitli', '[]'::jsonb) @> jsonb_build_array(sonuc -> 'halka')
                           then jsonb_build_object('kilitli', coalesce(durum -> 'kilitli', '[]'::jsonb) || (sonuc -> 'halka'))
                           else '{}'::jsonb end,
             guncelleme = now()
       where oyun_id = 'halka' and kullanici_id = u and anahtar = p_anahtar and not bitti;
    end if;
  end if;
  return sonuc;
end $$;
