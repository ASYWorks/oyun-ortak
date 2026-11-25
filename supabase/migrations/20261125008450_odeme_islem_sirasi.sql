-- Göç 8450 (D08, Codex incelemesi): ödeme hakkı mağaza işlemine ve olay sırasına bağlanır. İmza aynı; webhook değişmez.
-- 1) Olay kimliği işlemin BAŞINDA ayrılır. Eşzamanlı aynı olay birincinin işlemini bekler, sonra 'tekrar' döner (eskiden ikisi
--    de yan etkiyi uygulayabiliyordu; olay kaydı sonda yazılıyordu).
-- 2) İade yalnız aynı mağaza işlemine (dis_id) ait hakkı düşürür: eski alımın geç gelen iadesi yeniden alınmış hakka dokunmaz
--    ('eski_islem').
-- 3) Ters sıra: iadesi önce gelen işlemin satın alması hak vermez ('iade_edilmis'). İade edilen işlemler ayrı tabloda tutulur.
-- İşlem kimliği gelmeyen eski/elle olaylarda (dis_id null) davranış eskisi gibidir.
-- ponytail: sağlayıcıyla mutabakat (RevenueCat GET /subscribers) yok; sıra belirsizliği işlem kimliğiyle çözülüyor. Ödeme
-- açılınca haftalık mutabakat betiği eklenebilir.

create table ortak.iade_islemleri (
  dis_id text primary key,
  alindi timestamptz not null default now()
);
alter table ortak.iade_islemleri enable row level security;

create or replace function ortak.odeme_olayi(
  p_olay_id text, p_kullanici uuid, p_urun text, p_tur text, p_kaynak text, p_dis_id text default null
) returns text
language plpgsql security definer set search_path = '' as $$
declare u ortak.urunler; h ortak.haklar; v_sonuc text;
begin
  -- Ayır: aynı olay eşzamanlı gelirse ikinci insert birincinin işlemini bekler, sonra çakışır.
  insert into ortak.odeme_olaylari (olay_id, sonuc) values (p_olay_id, 'isleniyor') on conflict do nothing;
  if not found then return 'tekrar'; end if;

  select * into u from ortak.urunler where urun = p_urun;
  if not found then
    v_sonuc := 'urun_yok';
  elsif not exists (select 1 from auth.users where id = p_kullanici) then
    v_sonuc := 'kullanici_yok';
  elsif p_tur = 'ver' then
    if p_dis_id is not null and exists (select 1 from ortak.iade_islemleri where dis_id = p_dis_id) then
      v_sonuc := 'iade_edilmis';
    else
      insert into ortak.haklar (oyun_id, kullanici_id, hak, durum, kaynak, urun, dis_id)
      values (u.oyun_id, p_kullanici, u.hak, 'aktif', p_kaynak, p_urun, p_dis_id)
      on conflict (oyun_id, kullanici_id, hak) do update
        set durum = 'aktif', kaynak = excluded.kaynak, urun = excluded.urun, dis_id = excluded.dis_id, guncelleme = now();
      v_sonuc := 'ok';
    end if;
  elsif p_tur = 'iade' then
    if p_dis_id is not null then
      insert into ortak.iade_islemleri (dis_id) values (p_dis_id) on conflict do nothing;
    end if;
    select * into h from ortak.haklar where oyun_id = u.oyun_id and kullanici_id = p_kullanici and hak = u.hak for update;
    if found and p_dis_id is not null and h.dis_id is not null and h.dis_id <> p_dis_id then
      v_sonuc := 'eski_islem';
    else
      update ortak.haklar set durum = 'iade', guncelleme = now()
        where oyun_id = u.oyun_id and kullanici_id = p_kullanici and hak = u.hak;
      v_sonuc := 'ok';
    end if;
  else
    raise exception 'odeme_turu: %', p_tur;
  end if;
  update ortak.odeme_olaylari set sonuc = v_sonuc where olay_id = p_olay_id;
  return v_sonuc;
end $$;

revoke execute on all functions in schema ortak from public;
