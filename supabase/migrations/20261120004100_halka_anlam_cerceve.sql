-- Halka: anlam ipucu oyuncunun çerçevesinde (Halka genel incelemesi, bulgu 5). İstemci 39709ae'den beri anlam isteğinde
-- de p_rot, p_flip, p_kilitli gönderir ve p_sira oyuncunun yerleşimindeki dilimdir. Sunucu kilit ipucunun çerçevesini
-- (model.ts kilitCercevesi) bulur ve o çerçevede p_sira. dilimde okunan kelimenin anlamını verir. Böylece kaymış
-- yerleşimde de kurulmamış bir kelimenin anlamı gelir. Durum gelmezse eski davranış sürer.
-- Çerçeve seçimi kilit_sec'ten halka.cerceve'ye ayrıldı (davranış aynı). Kilitli halkalar halka.kilitliler'de.

-- Çözümün eşdeğerleri arasından kilitlilerle uyuşan, oyuncuyla en çok halkası aynı okunan: {rot: [], flip: []}.
create or replace function halka.cerceve(p_halkalar jsonb, p_cozum jsonb, p_kurallar jsonb, p_kilitli integer[],
                                         p_rot integer[], p_flip boolean[]) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  h int := jsonb_array_length(p_halkalar);
  n int := jsonb_array_length(p_halkalar -> 0);
  ayna boolean := coalesce((p_kurallar ->> 'flip')::boolean, false);
  kilitli int[] := coalesce(p_kilitli, '{}');
  oyuncu text[];
  m int; g int; r int; rr int; bf boolean;
  ayni int; uyar boolean; puan int; en int := -1;
  a_rot int[]; a_flip boolean[];
  t_rot int[]; t_flip boolean[];
begin
  oyuncu := array(select halka.sutun(p_halkalar -> x, p_rot[x + 1], p_flip[x + 1], n) from generate_series(0, h - 1) x order by x);
  -- equivalentStates: önce aynasız (m = 0), sonra ayna serbestse bütün halkalar ters (m = 1); her birinde g = 0..n-1.
  for m in 0 .. case when ayna then 1 else 0 end loop
    for g in 0 .. n - 1 loop
      a_rot := '{}'; a_flip := '{}'; ayni := 0; uyar := true;
      for r in 0 .. h - 1 loop
        bf := (p_cozum -> 'flip' ->> r)::boolean <> (m = 1);
        rr := (p_cozum -> 'rot' ->> r)::int;
        rr := ((case when bf then rr - g else rr + g end) % n + n) % n;
        a_rot := a_rot || rr;
        a_flip := a_flip || bf;
        if halka.sutun(p_halkalar -> r, rr, bf, n) = oyuncu[r + 1] then ayni := ayni + 1;
        elsif r = any (kilitli) then uyar := false;
        end if;
      end loop;
      puan := case when uyar then h + 1 else 0 end + ayni;
      if puan > en then en := puan; t_rot := a_rot; t_flip := a_flip; end if;
    end loop;
  end loop;
  return jsonb_build_object('rot', to_jsonb(t_rot), 'flip', to_jsonb(t_flip));
end $$;

-- Sıradaki kilit ipucu { halka, rot, flip } ya da null (model.ts kilitHalkasi). Çerçeve halka.cerceve'den.
create or replace function halka.kilit_sec(p_halkalar jsonb, p_cozum jsonb, p_kurallar jsonb, p_kilitli integer[],
                                           p_sira integer[], p_rot integer[], p_flip boolean[]) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  h int := jsonb_array_length(p_halkalar);
  n int := jsonb_array_length(p_halkalar -> 0);
  c jsonb := halka.cerceve(p_halkalar, p_cozum, p_kurallar, p_kilitli, p_rot, p_flip);
  r int; tr int; tf boolean;
begin
  foreach r in array coalesce(p_sira, '{}') || array(select x from generate_series(0, h - 1) x order by x) loop
    tr := (c -> 'rot' ->> r)::int;
    tf := (c -> 'flip' ->> r)::boolean;
    if not (r = any (coalesce(p_kilitli, '{}')))
       and halka.sutun(p_halkalar -> r, tr, tf, n) <> halka.sutun(p_halkalar -> r, p_rot[r + 1], p_flip[r + 1], n) then
      return jsonb_build_object('halka', r, 'rot', tr, 'flip', tf);
    end if;
  end loop;
  return null;
end $$;

-- Çerçevede k. dilimde okunan kelime (model.ts readRay: her halkanın tokenIndex'teki dilimi, ayraçsız).
create or replace function halka.dilim_oku(p_halkalar jsonb, p_cerceve jsonb, p_k integer) returns text
language sql immutable set search_path = '' as $$
  select string_agg(p_halkalar -> r ->> (case when (p_cerceve -> 'flip' ->> r)::boolean
                                              then (((p_cerceve -> 'rot' ->> r)::int - p_k) % n + n) % n
                                              else ((p_k + (p_cerceve -> 'rot' ->> r)::int) % n + n) % n end), '' order by r)
  from generate_series(0, jsonb_array_length(p_halkalar) - 1) r, (select jsonb_array_length(p_halkalar -> 0) as n) x
$$;

-- Kilitli halkalar: kurallardaki ∪ (istemci verdiyse onunki, yoksa bu denemede kilit ipucuyla verilenler).
create or replace function halka.kilitliler(p_anahtar text, p_kurallar jsonb, p_kilitli integer[]) returns integer[]
language sql stable security definer set search_path = '' as $$
  select array(select jsonb_array_elements_text(coalesce(p_kurallar -> 'locked', '[]'))::int)
    || case when p_kilitli is not null then array(select x from unnest(p_kilitli) x where x is not null)
            else array(select jsonb_array_elements_text(coalesce(
                   (select e.durum -> 'kilitli' from ortak.denemeler e
                     where e.oyun_id = 'halka' and e.kullanici_id = auth.uid() and e.anahtar = p_anahtar), '[]'))::int) end
$$;

revoke execute on function halka.cerceve(jsonb, jsonb, jsonb, integer[], integer[], boolean[]) from public, anon, authenticated;
revoke execute on function halka.dilim_oku(jsonb, jsonb, integer) from public, anon, authenticated;
revoke execute on function halka.kilitliler(text, jsonb, integer[]) from public, anon, authenticated;

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
  -- Duraklatılmış denemede ipucu yok: durdur nabzı geldiyse ya da nabızlı denemede son nabız 15 sn'den eskiyse.
  -- Nabızsız (eski istemci) denemede davranış aynı.
  if u is not null and exists (select 1 from ortak.denemeler e
      where e.oyun_id = 'halka' and e.kullanici_id = u and e.anahtar = p_anahtar and not e.bitti
        and (e.durdu or (e.son_nabiz is not null and e.son_nabiz < now() - interval '15 seconds'))) then
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
