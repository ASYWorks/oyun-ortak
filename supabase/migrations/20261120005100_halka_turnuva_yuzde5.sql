-- Usta Turnuvası Şampiyon rozeti ilk %10 yerine ilk %5'e (kurucu 18 Kasım: "Usta turnuvasında ilk %5 rozet alsın").
-- Yuvarlama ortak.siralama_odulu_ver'de değişmedi: greatest(ceil(katılımcı × oran), 1), az katılımda en az ilk sıra.
-- Eşitlikte aynı sıradakilerin hepsi alır (rank). Yalnız oran değişti.
create or replace function halka.turnuva_odul_ver() returns integer
language plpgsql security definer set search_path = '' as $$
declare t record; n int := 0;
begin
  for t in select kimlik from halka.turnuva_bulmacalar
           where halka.cevap_acik(bitir, now()) and bitir >= ortak.bugun() - 14 loop
    n := n + ortak.siralama_odulu_ver('halka', 'etkinlik', t.kimlik, 'sira:rozet-altin-' || t.kimlik, 0.05);
  end loop;
  return n;
end $$;
revoke execute on function halka.turnuva_odul_ver() from public, anon, authenticated;
