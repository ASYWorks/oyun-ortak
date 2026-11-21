-- Operatör paneli (panel.asyworks.com, 21 Kasım; ASYWorks/panel tasarımı): servis anahtarı panele konmaz.
-- ortak.panel_durumu(p_anahtar): gizli panel anahtarının sha256 özeti ortak.panel_ayar'daki özetle eşleşirse
-- ortak.isletim_durumu() + son yedek + auth kullanıcı sayısı döner; eşleşmezse null. Yazma yok.
-- ortak.yedek_kaydet: günlük yedek betiği (scripts/gunluk.sh) sonucu aynı anahtarla yazar; panel son yedeği buradan okur.
-- Anahtar sızsa bile yalnız durum özeti okunur ve yedek satırı eklenebilir. IP başına dakikada 30 çağrı.

create table ortak.panel_ayar (anahtar_ozet bytea not null);
alter table ortak.panel_ayar enable row level security;
revoke all on ortak.panel_ayar from anon, authenticated;

create table ortak.yedek_kayitlari (
  id bigserial primary key,
  zaman timestamptz not null default now(),
  proje text not null check (proje in ('canli', 'test')),
  basarili boolean not null,
  boyut_bayt bigint,
  "not" text check (char_length("not") <= 200)
);
alter table ortak.yedek_kayitlari enable row level security;
revoke all on ortak.yedek_kayitlari from anon, authenticated;
create index yedek_kayitlari_zaman on ortak.yedek_kayitlari (zaman);
select cron.schedule('ortak-yedek-kaydi-temizle', '40 3 * * *', $$delete from ortak.yedek_kayitlari where zaman < now() - interval '90 days'$$);

create function ortak.panel_anahtar_dogru(p_anahtar text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_anahtar is not null and exists (
    select 1 from ortak.panel_ayar where anahtar_ozet = extensions.digest(p_anahtar, 'sha256'))
$$;
revoke all on function ortak.panel_anahtar_dogru(text) from public, anon, authenticated;

create function ortak.panel_hiz() returns boolean
language sql volatile security definer set search_path = '' as $$
  select ortak.hiz_siniri('panel:' || coalesce(current_setting('request.headers', true)::jsonb ->> 'cf-connecting-ip', 'yerel'), 30, 60)
$$;
revoke all on function ortak.panel_hiz() from public, anon, authenticated;

create function ortak.panel_durumu(p_anahtar text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not ortak.panel_hiz() then raise exception 'cok_istek' using errcode = '54000'; end if;
  if not ortak.panel_anahtar_dogru(p_anahtar) then return null; end if;
  return ortak.isletim_durumu() || jsonb_build_object(
    'son_yedek', (select jsonb_build_object('zaman', y.zaman, 'basarili', y.basarili, 'boyut_bayt', y.boyut_bayt)
                  from ortak.yedek_kayitlari y where y.proje = 'canli' order by y.zaman desc limit 1),
    'auth_kullanici', (select count(*) from auth.users));
end $$;

create function ortak.yedek_kaydet(p_anahtar text, p_proje text, p_basarili boolean, p_boyut bigint, p_not text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not ortak.panel_hiz() then raise exception 'cok_istek' using errcode = '54000'; end if;
  if not ortak.panel_anahtar_dogru(p_anahtar) then raise exception 'anahtar_gecersiz' using errcode = '42501'; end if;
  insert into ortak.yedek_kayitlari (proje, basarili, boyut_bayt, "not") values (p_proje, p_basarili, p_boyut, left(p_not, 200));
end $$;

revoke all on function ortak.panel_durumu(text), ortak.yedek_kaydet(text, text, boolean, bigint, text) from public;
grant execute on function ortak.panel_durumu(text), ortak.yedek_kaydet(text, text, boolean, bigint, text) to anon, authenticated, service_role;
