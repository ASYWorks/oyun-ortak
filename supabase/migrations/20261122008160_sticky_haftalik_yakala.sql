-- Sticky haftalık ödül kendini yakalar (kurucu 22 Kasım, Sticky önerisi): iş her gün 03:05 İstanbul'da çalışır, geçen
-- haftanın ödülü zaten verildiyse hiçbir şey yapmaz. Pazartesi çalışması kaçarsa ya da yarım kalırsa ertesi gün tamamlanır;
-- sonradan ad alan biri 11. ödülü almaz (hafta için herhangi bir ödül varsa çıkılır). Elle p_hafta verilince koruma
-- atlanır, telafi yolu (select sticky.haftalik_odul('<pazartesi>')) aynen çalışır.
create or replace function sticky.haftalik_odul(p_hafta date default null) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  hafta date := coalesce(p_hafta, (date_trunc('week', now() at time zone 'Europe/Istanbul') - interval '7 days')::date);
  bas timestamptz := hafta::timestamp at time zone 'Europe/Istanbul';
  bit timestamptz := (hafta + 7)::timestamp at time zone 'Europe/Istanbul';
  n integer;
begin
  if p_hafta is null and exists (select 1 from ortak.oduller where oyun_id = 'sticky' and kaynak = 'hafta:' || hafta) then
    return 0;
  end if;
  with s as (
    select l.user_id, row_number() over (order by sum(l.delta) desc, count(*) desc, o.ad asc) as sira
    from sticky.rating_log l
    join ortak.oyuncular o on o.oyun_id = 'sticky' and o.kullanici_id = l.user_id and o.ad is not null
    where l.at >= bas and l.at < bit
    group by l.user_id, o.ad having count(*) >= 5
  )
  insert into ortak.oduller (oyun_id, kullanici_id, odul, kaynak)
    select 'sticky', user_id, 'sira:hafta-ilk10:' || hafta, 'hafta:' || hafta from s where sira <= 10
    union all
    select 'sticky', user_id, 'sira:hafta-ilk3:' || hafta, 'hafta:' || hafta from s where sira <= 3
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

select cron.unschedule('sticky-haftalik-odul');
select cron.schedule('sticky-haftalik-odul', '5 0 * * *', $$select sticky.haftalik_odul()$$);  -- her gün 03:05 İstanbul, yalnız eksikse verir
