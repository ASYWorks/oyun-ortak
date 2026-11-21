-- Halka adil puan (HK-21; ISTEKLER.md PU-3, PU-5, PU-6, İP-2). Kaynak: halka-kelime supabase/hk21_puan.sql (7d4c0c8),
-- testi halka-kelime tests/sql.test.ts "hk21".
-- 1) Zorluk sunucuda: halka.gunluk_bulmacalar.zorluk / halka.turnuva_bulmacalar.zorluk. Yükleme işlevleri yazar,
--    halka_dogrula_bulmaca / halka_dogrula_turnuva döndürür; dogrula-halka hedef süreyi buradan hesaplar
--    (boşsa orta zorluk).
-- 2) İP-2: bulmaca başına en çok 2 kilit ipucu; hak bitince halka.ipucu_ver kilit vermez (null).
--    Deneme satırı kilitlenir: aynı anda gelen iki istek hakkı aşamaz.

alter table halka.gunluk_bulmacalar add column if not exists zorluk integer;
alter table halka.turnuva_bulmacalar add column if not exists zorluk integer;

-- ---------------------------------------------------------------- yükleme: + zorluk (hk20 gövdeleri)

create or replace function public.halka_gunluk_yukle(p_satirlar jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  insert into halka.gunluk_bulmacalar (tarih, halkalar, cevaplar, cozum, anlamlar, kilit_sirasi, ek, hedef, baslangic, kurallar, tema, zorluk)
  select x.tarih, x.halkalar, x.cevaplar, x.cozum, x.anlamlar, x.kilit_sirasi, x.ek, x.hedef, x.baslangic, x.kurallar, x.tema, x.zorluk
  from jsonb_to_recordset(p_satirlar) as x(tarih date, halkalar jsonb, cevaplar text[], cozum jsonb, anlamlar jsonb,
                                           kilit_sirasi integer[], ek jsonb, hedef integer, baslangic jsonb, kurallar jsonb, tema text, zorluk integer)
  on conflict (tarih) do update set halkalar = excluded.halkalar, cevaplar = excluded.cevaplar, cozum = excluded.cozum,
    anlamlar = excluded.anlamlar, kilit_sirasi = excluded.kilit_sirasi, ek = excluded.ek, hedef = excluded.hedef,
    baslangic = excluded.baslangic, kurallar = excluded.kurallar, tema = excluded.tema, zorluk = excluded.zorluk;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.halka_turnuva_yukle(p_satirlar jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  insert into halka.turnuva_bulmacalar (kimlik, basla, bitir, halkalar, cevaplar, cozum, anlamlar, kilit_sirasi, ek, hedef, baslangic, kurallar, tema, zorluk)
  select x.kimlik, x.basla, x.bitir, x.halkalar, x.cevaplar, x.cozum, x.anlamlar, x.kilit_sirasi, x.ek, x.hedef, x.baslangic, x.kurallar, x.tema, x.zorluk
  from jsonb_to_recordset(p_satirlar) as x(kimlik text, basla date, bitir date, halkalar jsonb, cevaplar text[], cozum jsonb,
                                           anlamlar jsonb, kilit_sirasi integer[], ek jsonb, hedef integer, baslangic jsonb, kurallar jsonb, tema text, zorluk integer)
  on conflict (kimlik) do update set basla = excluded.basla, bitir = excluded.bitir, halkalar = excluded.halkalar,
    cevaplar = excluded.cevaplar, cozum = excluded.cozum, anlamlar = excluded.anlamlar, kilit_sirasi = excluded.kilit_sirasi,
    ek = excluded.ek, hedef = excluded.hedef, baslangic = excluded.baslangic, kurallar = excluded.kurallar, tema = excluded.tema, zorluk = excluded.zorluk;
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------- dogrula-halka: + zorluk (hk14 / hk16 gövdeleri)

create or replace function public.halka_dogrula_bulmaca(p_tarih date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('halkalar', g.halkalar, 'cevaplar', to_jsonb(g.cevaplar), 'hedef', g.hedef,
                            'baslangic', g.baslangic, 'kurallar', g.kurallar, 'cozum', g.cozum, 'zorluk', g.zorluk)
  from halka.gunluk_bulmacalar g where g.tarih = p_tarih
$$;

create or replace function public.halka_dogrula_turnuva(p_kimlik text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('halkalar', t.halkalar, 'cevaplar', to_jsonb(t.cevaplar), 'hedef', t.hedef,
                            'baslangic', t.baslangic, 'kurallar', t.kurallar, 'cozum', t.cozum, 'basla', t.basla, 'bitir', t.bitir,
                            'zorluk', t.zorluk)
  from halka.turnuva_bulmacalar t where t.kimlik = p_kimlik
$$;

revoke execute on function public.halka_gunluk_yukle(jsonb), public.halka_turnuva_yukle(jsonb),
  public.halka_dogrula_bulmaca(date), public.halka_dogrula_turnuva(text) from public, anon, authenticated;
grant execute on function public.halka_gunluk_yukle(jsonb), public.halka_turnuva_yukle(jsonb),
  public.halka_dogrula_bulmaca(date), public.halka_dogrula_turnuva(text) to service_role;

-- ---------------------------------------------------------------- ipucu gövdesi: + kilit hakkı (hk20 gövdesi)

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

revoke execute on function halka.ipucu_ver(text, jsonb, text[], jsonb, jsonb, integer[], jsonb, text, integer, integer[], boolean[], integer[], text)
  from public, anon, authenticated;
