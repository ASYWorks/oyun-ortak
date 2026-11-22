-- Göç 8230: arkadaş silme ada bağlıydı (otomatik güvenlik incelemesi, 22 Kasım): adı olmayan ya da adı değişen arkadaş
-- silinemiyordu. Her arkadaşlık satırına rastgele, kullanıcı kimliği olmayan bir tutamaç eklenir; koz_arkadaslar onu da
-- döner, silme tutamaçla yapılır. Tutamaç yalnız sahibinin satırında işe yarar.

alter table koz.arkadaslik add column tutamac uuid not null default gen_random_uuid() unique;

drop function public.koz_arkadas_sil(text);

create or replace function public.koz_arkadaslar() returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid := koz.kalici_kim();
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('tutamac', r.tutamac, 'ad', o.ad) order by o.ad nulls last), '[]'::jsonb)
          from koz.arkadaslik r left join ortak.oyuncular o on o.oyun_id = 'koz' and o.kullanici_id = r.arkadas
          where r.kullanici = u);
end $$;

create function public.koz_arkadas_sil(p_tutamac uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare u uuid := koz.kalici_kim(); a uuid;
begin
  select arkadas into a from koz.arkadaslik where kullanici = u and tutamac = p_tutamac;
  if a is null then return jsonb_build_object('hata', 'arkadas_yok'); end if;
  delete from koz.arkadaslik where (kullanici = u and arkadas = a) or (kullanici = a and arkadas = u);
  return jsonb_build_object('tamam', true);
end $$;

revoke all on function public.koz_arkadas_sil(uuid) from public, anon;
grant execute on function public.koz_arkadas_sil(uuid) to authenticated;
