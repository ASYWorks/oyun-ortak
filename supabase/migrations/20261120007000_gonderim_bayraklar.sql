-- Sunucu kontrollü bayraklar gönderimde de (Halka isteği, 20 Kasım): halka_gonderim_verisi yanıtına oyunun bayrakları
-- eklenir; dogrula-halka kapalı özelliğin (ör. "turnuva") gönderimini 403 "kapali" ile reddeder. Alan yoksa {}.
create or replace function public.halka_gonderim_verisi(p_tur text, p_donem text, p_anahtar text, p_kullanici uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'bulmaca', case when p_tur = 'gunluk' then public.halka_dogrula_bulmaca(p_donem::date)
                    when p_tur = 'etkinlik' then public.halka_dogrula_turnuva(p_donem) end,
    'deneme', (select jsonb_build_object('sira', d.sira, 'durum', d.durum, 'bitti', d.bitti, 'olusturma', d.olusturma,
                                         'aktif_ms', d.aktif_ms, 'son_nabiz', d.son_nabiz, 'durak_ms', d.durak_ms)
               from ortak.denemeler d where d.oyun_id = 'halka' and d.kullanici_id = p_kullanici and d.anahtar = p_anahtar),
    'bayraklar', coalesce((select ayarlar -> 'bayraklar' from ortak.oyunlar where id = 'halka'), '{}'::jsonb))
$$;
revoke execute on function public.halka_gonderim_verisi(text, text, text, uuid) from public, anon, authenticated;
grant execute on function public.halka_gonderim_verisi(text, text, text, uuid) to service_role;
