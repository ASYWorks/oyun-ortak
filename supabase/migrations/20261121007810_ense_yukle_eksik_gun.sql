-- Göç 7810: ense_gunluk_yukle hiç yüklenmemiş günü (bugün ya da geçmiş) ekleyebilir; var olan açılmış güne dokunmaz.
-- 7800'de bugün ve öncesi tümden atlanıyordu; içerik geç yüklenirse bugünün görevi hiç oluşmuyordu (Ense, 21 Kasım).
create or replace function public.ense_gunluk_yukle(p_satirlar jsonb, p_surum text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare yazilan int; toplam int := jsonb_array_length(p_satirlar);
begin
  with girdi as (
    select (x ->> 'gun')::date as gun, x -> 'resmi' as resmi, x -> 'prova' as prova
    from jsonb_array_elements(p_satirlar) x
  ), yaz as (
    insert into ense.gunluk as g (gun, resmi, prova, icerik_surumu)
    select gun, resmi, prova, p_surum from girdi
    on conflict (gun) do update set resmi = excluded.resmi, prova = excluded.prova, icerik_surumu = excluded.icerik_surumu, yukleme = now()
      where g.gun > ortak.bugun()   -- açılmış gün güncellenmez (tetikleyici de korur)
    returning 1
  ) select count(*) into yazilan from yaz;
  return jsonb_build_object('yazilan', yazilan, 'atlanan', toplam - yazilan, 'son_gun', (select max(gun) from ense.gunluk));
end $$;
revoke all on function public.ense_gunluk_yukle(jsonb, text) from public, anon, authenticated;
grant execute on function public.ense_gunluk_yukle(jsonb, text) to service_role;
