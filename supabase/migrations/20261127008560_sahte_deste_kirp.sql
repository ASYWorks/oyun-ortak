-- Göç 8560 (SM-8): Sahte Masası takvim kırpma. Havuz günlük ve seviye olarak bölündü (dalga 4 C), takvim kaydığı için
-- yükleme öncesi açılmamış gelecek günler silinir (desteler.no tekil; kayan takvimde upsert 23505 verir).
-- Bugün ve yarın hiçbir zaman silinmez; açılmış günü zaten sahte.acilmis_gun_koru korur. Her silme yonetim kaydına düşer.

create function public.sahte_deste_kirp(p_son date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  n integer;
begin
  if p_son is null then raise exception 'p_son_gerekli' using errcode = '22023'; end if;
  delete from sahte.desteler where gun > greatest(p_son, ortak.bugun() + 1);
  get diagnostics n = row_count;
  return jsonb_build_object('silinen', n, 'son_gun', (select max(gun) from sahte.desteler));
end $$;
revoke all on function public.sahte_deste_kirp(date) from public, anon, authenticated;
grant execute on function public.sahte_deste_kirp(date) to service_role;
