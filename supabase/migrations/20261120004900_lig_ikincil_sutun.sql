-- Lig tablosunda eşitlik bozucu sütunu (Halka isteği, kurucu 18 Kasım: "eşitlikte süreye bakılacaksa sütun olarak tabloda olsun").
-- uyeler satırına `ikincil` eklenir: sıralamada kullanılan ham değer (en iyi N günün skorlar.ikincil toplamı,
-- lig_puani_guncelle). Birimi oyuna aittir (Halka v4: süre×1000+hamle; saniye = floor(ikincil/1000)).
-- Oyunun lig eşitliği 'ikincil' değilse null. Başka değişiklik yok.
create or replace function ortak.lig_durumu(p_oyun text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  u uuid := ortak.kim();
  v_hafta date := ortak.iso_hafta(ortak.bugun());
  a jsonb;
  g bigint;
  o ortak.oyuncular;
  onceki jsonb;
  uyeler jsonb;
begin
  select ayarlar -> 'lig' into a from ortak.oyunlar where id = p_oyun;
  if a is null then raise exception 'lig_yok'; end if;
  select * into o from ortak.oyuncular where oyun_id = p_oyun and kullanici_id = u;
  select jsonb_build_object('hafta', l.hafta, 'sira', l.sira, 'sonuc', l.sonuc, 'puan', l.puan) into onceki
    from ortak.lig_uyeleri l join ortak.lig_gruplari gr on gr.id = l.grup_id
    where l.oyun_id = p_oyun and l.kullanici_id = u and gr.kapandi
    order by l.hafta desc limit 1;
  select grup_id into g from ortak.lig_uyeleri where oyun_id = p_oyun and hafta = v_hafta and kullanici_id = u;

  if g is not null then
    select jsonb_agg(jsonb_build_object('sira', x.sira, 'ad', x.ad, 'puan', x.puan, 'ikincil', x.ikincil, 'ben', x.ben) order by x.sira, x.ad)
    into uyeler from (
      select rank() over (order by l.puan desc,
               case when coalesce(a ->> 'esitlik', 'ortak') = 'ikincil' then l.ikincil end asc nulls last) as sira,
             oy.ad, l.puan,
             case when coalesce(a ->> 'esitlik', 'ortak') = 'ikincil' then l.ikincil end as ikincil,
             l.kullanici_id = u as ben
      from ortak.lig_uyeleri l
      left join ortak.oyuncular oy on oy.oyun_id = p_oyun and oy.kullanici_id = l.kullanici_id
      where l.grup_id = g) x;
  end if;

  return jsonb_build_object(
    'hafta', v_hafta,
    'kademe', coalesce(o.kademe, 0),
    'kademe_adi', a -> 'kademeler' ->> coalesce(o.kademe, 0),
    'katildi', g is not null,
    'uyeler', coalesce(uyeler, '[]'::jsonb),
    'onceki', onceki);
end $$;
revoke execute on function ortak.lig_durumu(text) from public, anon;
grant execute on function ortak.lig_durumu(text) to authenticated;
