-- Ölçek (Halka OL-1, OL-2; 17 Kasım 2026).
-- OL-1: lig_ata açık grubu danışma kilidi altında bütün grupları sayarak arıyordu (O(grup)); Pazartesi 00:00'da herkesin
-- haftalık ilk gönderimi bu kilitte sıraya girer. Artık yalnız son açık grubun üye sayısına bakılır.
-- OL-2: hız sınırı sayaçları UNLOGGED (her edge çağrısı ve nabız bir yazım; kaybolursa sayaç sıfırlanır, zarar yok).

alter table ortak.hiz_sinirlari set unlogged;

create or replace function ortak.lig_ata(p_oyun text, p_kullanici uuid, p_hafta date) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  a jsonb;
  o ortak.oyuncular;
  v_bant integer;
  boy integer;
  g bigint;
begin
  select grup_id into g from ortak.lig_uyeleri where oyun_id = p_oyun and hafta = p_hafta and kullanici_id = p_kullanici;
  if g is not null then return g; end if;

  select ayarlar -> 'lig' into a from ortak.oyunlar where id = p_oyun;
  if a is null then return null; end if;
  select * into o from ortak.oyuncular where oyun_id = p_oyun and kullanici_id = p_kullanici;
  v_bant := case when coalesce((a ->> 'bant_genisligi')::int, 0) > 0
                 then coalesce(o.seviye_puani, 0) / (a ->> 'bant_genisligi')::int else 0 end;
  boy := coalesce((a ->> 'grup_boyu')::int, 50);

  perform pg_advisory_xact_lock(hashtextextended(p_oyun || '|' || p_hafta || '|' || coalesce(o.kademe, 0) || '|' || v_bant, 0));

  -- Gruplar bu kilit altında sırayla dolar: yalnız son açık gruba bakılır (silmeyle boşalan eski yerler doldurulmaz).
  select gr.id into g from ortak.lig_gruplari gr
  where gr.oyun_id = p_oyun and gr.hafta = p_hafta and gr.kademe = coalesce(o.kademe, 0) and gr.bant = v_bant
    and not gr.kapandi
  order by gr.id desc limit 1;
  if g is not null and (select count(*) from ortak.lig_uyeleri u where u.grup_id = g) >= boy then g := null; end if;
  if g is null then
    insert into ortak.lig_gruplari (oyun_id, hafta, kademe, bant)
    values (p_oyun, p_hafta, coalesce(o.kademe, 0), v_bant) returning id into g;
  end if;
  insert into ortak.lig_uyeleri (grup_id, oyun_id, hafta, kullanici_id) values (g, p_oyun, p_hafta, p_kullanici);
  return g;
end $$;
