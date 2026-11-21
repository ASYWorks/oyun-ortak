-- Halka: duraklatılmış denemede ipucu verilmez (kurucu 16 Kasım 2026: "Duraklatınca tahtaya bakamasın, en azından
-- ipucu da kullanamasın"). halka.ipucu_ver nabızlı denemede son nabız 15 sn'den eskiyse 'duraklatildi' hatası verir,
-- ipucu yazılmaz. Gövde 20261120002600 ile aynı, yalnız bu denetim eklendi.
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
begin
  -- Duraklatılmış denemede ipucu yok (kurucu 16 Kasım 2026): nabızlı denemede son nabız 15 sn'den eskiyse.
  -- Nabızsız (eski istemci) denemede davranış aynı.
  if u is not null and exists (select 1 from ortak.denemeler e
      where e.oyun_id = 'halka' and e.kullanici_id = u and e.anahtar = p_anahtar and not e.bitti
        and e.son_nabiz is not null and e.son_nabiz < now() - interval '15 seconds') then
    raise exception 'duraklatildi' using errcode = 'P0001';
  end if;
  if p_tur = 'anlam' then
    sonuc := case when p_anlamlar ->> p_cevaplar[p_sira + 1] is not null
                  then jsonb_build_object('anlam', p_anlamlar ->> p_cevaplar[p_sira + 1]) end;
  elsif p_tur = 'kilit' then
    if p_cozum is null then return null; end if;
    -- Hak (src/puan.ts IPUCU_HAK.kilit): bitince ipucu yok (istemci pencerede satırı kapatır; dogrula-halka fazlasını 422 ile reddeder).
    if u is not null then
      perform 1 from ortak.denemeler where oyun_id = 'halka' and kullanici_id = u and anahtar = p_anahtar for update;
    end if;
    if u is not null and (select count(*) from ortak.denemeler e, jsonb_array_elements_text(coalesce(e.durum -> 'ipuclari', '[]')) x
                          where e.oyun_id = 'halka' and e.kullanici_id = u and e.anahtar = p_anahtar and x = 'kilit') >= 2 then
      return null;
    end if;
    if p_rot is not null or p_flip is not null then
      if not halka.durum_gecerli(jsonb_array_length(p_halkalar), p_rot, p_flip) then
        raise exception 'gecersiz_durum' using errcode = '22023';
      end if;
      d := ortak.deneme_al('halka', u, p_anahtar);
      sonuc := halka.kilit_sec(p_halkalar, p_cozum, p_kurallar,
        array(select jsonb_array_elements_text(coalesce(p_kurallar -> 'locked', '[]'))::int)
          || case when p_kilitli is not null then array(select x from unnest(p_kilitli) x where x is not null)
                  else array(select jsonb_array_elements_text(coalesce(d.durum -> 'kilitli', '[]'))::int) end,
        p_kilit_sirasi, p_rot, p_flip);
    else
      sira := coalesce(p_kilit_sirasi, '{}')
        || array(select g from generate_series(0, jsonb_array_length(p_halkalar) - 1) g
                 where g <> all (coalesce(p_kilit_sirasi, '{}')) order by g);
      r := sira[p_sira + 1];
      if r is not null then
        sonuc := jsonb_build_object('halka', r, 'rot', p_cozum -> 'rot' -> r, 'flip', p_cozum -> 'flip' -> r);
      end if;
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
