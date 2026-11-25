-- Göç 8460 (D03 sunucu makbuzu, Codex incelemesi): devir yapılıp yanıt kaybolursa istemci aynı kodla yeniden çağırır.
-- Eskiden kod silindiği için 'devir_kodu_gecersiz' dönüyor ve istemci başarısız sayıyordu. Şimdi başarılı devrin sonucu
-- (kod özeti + hedef hesap) 30 dk saklanır; aynı hesap aynı kodla çağırırsa aynı sonuç döner. Başka hesap için kod yine geçersiz.
-- İmza aynı: ortak.hesap_devral(text) returns jsonb. Asıl iş hesap_devral_ic'e taşındı (istemciye kapalı).

create table ortak.devir_makbuzlari (
  kod_ozeti bytea primary key,
  hedef uuid not null,
  sonuc jsonb not null,
  bitis timestamptz not null
);
alter table ortak.devir_makbuzlari enable row level security;

alter function ortak.hesap_devral(text) rename to hesap_devral_ic;
revoke all on function ortak.hesap_devral_ic(text) from public, anon, authenticated;

create function ortak.hesap_devral(p_kod text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  ozet bytea := sha256(convert_to(p_kod, 'UTF8'));
  m ortak.devir_makbuzlari;
  r jsonb;
begin
  select * into m from ortak.devir_makbuzlari where kod_ozeti = ozet and bitis > now();
  if found then
    if m.hedef = ortak.kim() then return m.sonuc; end if;
    raise exception 'devir_kodu_gecersiz';
  end if;
  r := ortak.hesap_devral_ic(p_kod);
  delete from ortak.devir_makbuzlari where bitis < now();
  insert into ortak.devir_makbuzlari values (ozet, ortak.kim(), r, now() + interval '30 minutes')
    on conflict (kod_ozeti) do nothing;
  return r;
end $$;

revoke all on function ortak.hesap_devral(text) from public, anon;
grant execute on function ortak.hesap_devral(text) to authenticated;
revoke execute on all functions in schema ortak from public;
