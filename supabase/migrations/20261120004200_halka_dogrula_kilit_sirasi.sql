-- dogrula-halka kilit hamlesini denetlesin (Halka genel incelemesi, bulgu 4): bulmaca kaydı kilit_sirasi'ni da verir.
-- Oyunun oynat'ı lockOrder gelince kilit hamlesindeki halkayı kilitHalkasi'nın o anki seçimiyle karşılaştırır
-- (halka.kilit_sec ile aynı kural). Sıra yoksa alan gelmez, eski davranış sürer.

create or replace function public.halka_dogrula_bulmaca(p_tarih date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('halkalar', g.halkalar, 'cevaplar', to_jsonb(g.cevaplar), 'hedef', g.hedef,
                            'baslangic', g.baslangic, 'kurallar', g.kurallar, 'cozum', g.cozum, 'zorluk', g.zorluk)
         || jsonb_strip_nulls(jsonb_build_object('kilit_sirasi', to_jsonb(g.kilit_sirasi)))
  from halka.gunluk_bulmacalar g where g.tarih = p_tarih
$$;

create or replace function public.halka_dogrula_turnuva(p_kimlik text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('halkalar', t.halkalar, 'cevaplar', to_jsonb(t.cevaplar), 'hedef', t.hedef,
                            'baslangic', t.baslangic, 'kurallar', t.kurallar, 'cozum', t.cozum, 'basla', t.basla, 'bitir', t.bitir,
                            'zorluk', t.zorluk)
         || jsonb_strip_nulls(jsonb_build_object('kilit_sirasi', to_jsonb(t.kilit_sirasi)))
  from halka.turnuva_bulmacalar t where t.kimlik = p_kimlik
$$;
