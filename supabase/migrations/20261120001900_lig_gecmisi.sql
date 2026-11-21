-- HK-13 (Halka, 15 Kasım 2026): oyuncunun geçmiş lig haftaları (açıp bakılabilen sıralama ekranı). Kapanmış haftalar,
-- yeniden eskiye, en çok 26: hafta, o haftaki kademe ve adı, sıra, sonuç, puan, grup büyüklüğü. Misafir ligde
-- olmadığı için boş döner. Bitmiş etkinliğin sıralaması zaten `siralama('etkinlik', <kimlik>)` ile okunur.
create function ortak.lig_gecmisi(p_oyun text, p_hafta_sayisi integer default 8) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(x.j order by x.hafta desc), '[]'::jsonb)
  from (
    select l.hafta, jsonb_build_object(
      'hafta', l.hafta, 'kademe', gr.kademe,
      'kademe_adi', (select o.ayarlar -> 'lig' -> 'kademeler' ->> gr.kademe from ortak.oyunlar o where o.id = p_oyun),
      'sira', l.sira, 'sonuc', l.sonuc, 'puan', l.puan,
      'kisi', (select count(*) from ortak.lig_uyeleri u where u.grup_id = l.grup_id)) as j
    from ortak.lig_uyeleri l join ortak.lig_gruplari gr on gr.id = l.grup_id
    where l.oyun_id = p_oyun and l.kullanici_id = ortak.kim() and gr.kapandi
    order by l.hafta desc
    limit least(greatest(coalesce(p_hafta_sayisi, 8), 1), 26)
  ) x
$$;
revoke execute on function ortak.lig_gecmisi(text, integer) from public, anon;
grant execute on function ortak.lig_gecmisi(text, integer) to authenticated;
