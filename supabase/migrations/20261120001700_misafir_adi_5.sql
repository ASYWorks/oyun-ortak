-- Misafir/otomatik ad 7 yerine 5 karakter (kurucu, 15 Kasım 2026): `#` + 5 karakter, ör. #K7P2X (~33 milyon ad).
-- Gerekirse sonra artırılır. Var olan 7 karakterli otomatik adlar 5'e çevrilir (yayın öncesi).
create or replace function ortak.misafir_kodu() returns text
language sql volatile set search_path = '' as $$
  select '#' || string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '')
  from generate_series(1, 5)
$$;
revoke execute on function ortak.misafir_kodu() from public, anon, authenticated;

do $$
declare r record; v text;
begin
  for r in select oyun_id, kullanici_id from ortak.oyuncular where ad_otomatik and ad ~ '^#[A-Z2-9]{7}$' loop
    for i in 1..10 loop
      v := ortak.misafir_kodu();
      begin
        update ortak.oyuncular set ad = v, ad_anahtari = ortak.ad_anahtari(v)
          where oyun_id = r.oyun_id and kullanici_id = r.kullanici_id;
        exit;
      exception when unique_violation then null;
      end;
    end loop;
  end loop;
end $$;
