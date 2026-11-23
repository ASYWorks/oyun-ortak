-- Göç 8400: panel notları (kurucu 23 Kasım). Kurucu oyunları denerken aldığı notları panel.asyworks.com'da oyun oyun girer;
-- oyun-ortak oturumu "gönder" denince yeni notları ilgili oyun oturumuna iletir (scripts/panel-notlar.mjs) ve durumu günceller.
-- Panel servis anahtarı taşımaz: ekleme, listeleme ve henüz gönderilmemiş notu silme panel anahtarıyla (7500'deki gibi).
-- Durum (gonderildi, yapildi) ve sonuç yalnız servis rolüyle değişir. Oyun kimliği oyunun klasör adıdır (panel SITELER.proje).

create table ortak.panel_notlar (
  id bigserial primary key,
  oyun text not null check (oyun ~ '^[a-z0-9][a-z0-9-]{1,40}$'),
  metin text not null check (char_length(btrim(metin)) between 1 and 4000),
  durum text not null default 'yeni' check (durum in ('yeni', 'gonderildi', 'yapildi')),
  olusturma timestamptz not null default now(),
  gonderildi timestamptz,
  sonuc text check (char_length(sonuc) <= 1000)
);
alter table ortak.panel_notlar enable row level security;
revoke all on ortak.panel_notlar from anon, authenticated;
create index panel_notlar_oyun on ortak.panel_notlar (oyun, olusturma desc);

create function ortak.panel_not_ekle(p_anahtar text, p_oyun text, p_metin text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v bigint;
begin
  if not ortak.panel_hiz() then raise exception 'cok_istek' using errcode = '54000'; end if;
  if not ortak.panel_anahtar_dogru(p_anahtar) then return null; end if;
  insert into ortak.panel_notlar (oyun, metin) values (p_oyun, btrim(p_metin)) returning id into v;
  return v;
end $$;

-- Son 300 not (yapılanlar dahil), yeniden eskiye.
create function ortak.panel_notlar(p_anahtar text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not ortak.panel_hiz() then raise exception 'cok_istek' using errcode = '54000'; end if;
  if not ortak.panel_anahtar_dogru(p_anahtar) then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'oyun', n.oyun, 'metin', n.metin, 'durum', n.durum,
                                                       'olusturma', n.olusturma, 'gonderildi', n.gonderildi, 'sonuc', n.sonuc)
                                    order by n.olusturma desc)
                     from (select * from ortak.panel_notlar order by olusturma desc limit 300) n), '[]'::jsonb);
end $$;

-- Yalnız henüz gönderilmemiş not silinir; true silindi, false silinemedi (yok ya da gönderilmiş), null anahtar yanlış.
create function ortak.panel_not_sil(p_anahtar text, p_id bigint) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if not ortak.panel_hiz() then raise exception 'cok_istek' using errcode = '54000'; end if;
  if not ortak.panel_anahtar_dogru(p_anahtar) then return null; end if;
  delete from ortak.panel_notlar where id = p_id and durum = 'yeni';
  return found;
end $$;

revoke all on function ortak.panel_not_ekle(text, text, text), ortak.panel_notlar(text), ortak.panel_not_sil(text, bigint) from public;
grant execute on function ortak.panel_not_ekle(text, text, text), ortak.panel_notlar(text), ortak.panel_not_sil(text, bigint)
  to anon, authenticated, service_role;
