-- Göç 8250: dogrula-koz düello elini havuzdan okur (Koz isteği, 22 Kasım). Yalnız servis rolü; kullanıcı düellonun tarafı
-- değilse ya da sıra dışındaysa null. p_sira 0 tabanlı.
create function public.koz_duello_el(p_kullanici uuid, p_duello uuid, p_sira int) returns jsonb
language sql stable security definer set search_path = '' as $$
  select h.kayit from koz.duello d join koz.duello_havuz h on h.id = d.eller[p_sira + 1]
  where d.id = p_duello and p_kullanici in (d.acan, d.rakip) and p_sira >= 0 and p_sira < cardinality(d.eller)
$$;
revoke all on function public.koz_duello_el(uuid, uuid, int) from public, anon, authenticated;
grant execute on function public.koz_duello_el(uuid, uuid, int) to service_role;
