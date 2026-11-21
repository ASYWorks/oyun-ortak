-- Sticky Ten istekleri (ISTEKLER.md, 16 Kasım 2026, kurucu).
-- ST-10: sticky.puanli_sonuc_yaz: bir puanlı oyunun bütün rating parçaları (stats, rating_log, rated_pairs) tek
--        işlemde ve oyun kimliğiyle bir kez yazılır. Aynı oyun kimliği ikinci kez gelirse (sunucu devri, yeniden
--        deneme) hiçbir şey yazılmaz, ilk sonuç `tekrar: true` ile döner. Aynı anda gelen iki çağrıdan biri bekler,
--        sonra ilk sonucu görür. Kayıt 7 gün tutulur. Yalnız servis rolü. rating_uygula'nın yerini alır.
-- ST-11: eşitlikte sabit sıra: değer, oyun sayısı, sonra ad (ad oyun içinde benzersiz). siralama ve haftalık ödül
--        aynı sırayı kullanır.

create table sticky.puanli_oyunlar (
  oyun uuid primary key,
  gun text not null,
  sonuc jsonb not null default '[]',
  at timestamptz not null default now()
);
create index puanli_oyunlar_at on sticky.puanli_oyunlar (at);
alter table sticky.puanli_oyunlar enable row level security;
alter table sticky.rating_log add column if not exists oyun uuid;

-- p_oyuncular: [{ kullanici, delta }]. p_ikililer: rated_pairs anahtarları.
-- Dönüş: { oyun, tekrar, oyuncular: [{ kullanici, delta, rating, rated_games, rated_today }] }.
create function sticky.puanli_sonuc_yaz(p_oyun uuid, p_gun text, p_oyuncular jsonb, p_ikililer text[] default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare x jsonb; u uuid; d real; r record; v_sonuc jsonb := '[]'; eski jsonb;
begin
  if p_oyun is null or p_gun is null or p_gun !~ '^\d{4}-\d{2}-\d{2}$' or jsonb_typeof(p_oyuncular) is distinct from 'array' then
    raise exception 'gecersiz';
  end if;
  insert into sticky.puanli_oyunlar (oyun, gun) values (p_oyun, p_gun) on conflict (oyun) do nothing;
  if not found then
    select sonuc into eski from sticky.puanli_oyunlar where oyun = p_oyun;
    return jsonb_build_object('oyun', p_oyun, 'tekrar', true, 'oyuncular', eski);
  end if;
  for x in select * from jsonb_array_elements(p_oyuncular) loop
    u := (x ->> 'kullanici')::uuid;
    d := (x ->> 'delta')::real;
    if u is null or d is null then raise exception 'gecersiz'; end if;
    insert into sticky.stats as s (user_id, rating, rated_games, rated_day, rated_today)
      values (u, 1200 + d, 1, p_gun, 1)
      on conflict (user_id) do update set
        rating = s.rating + d,
        rated_games = s.rated_games + 1,
        rated_today = case when s.rated_day = p_gun then s.rated_today + 1 else 1 end,
        rated_day = p_gun
      returning s.rating, s.rated_games, s.rated_today into r;
    insert into sticky.rating_log (user_id, delta, oyun) values (u, d, p_oyun);
    v_sonuc := v_sonuc || jsonb_build_object('kullanici', u, 'delta', d, 'rating', r.rating,
                                             'rated_games', r.rated_games, 'rated_today', r.rated_today);
  end loop;
  if cardinality(p_ikililer) > 0 then
    insert into sticky.rated_pairs (pair) select unnest(p_ikililer);
  end if;
  update sticky.puanli_oyunlar set sonuc = v_sonuc where oyun = p_oyun;
  delete from sticky.puanli_oyunlar where at < now() - interval '7 days';
  return jsonb_build_object('oyun', p_oyun, 'tekrar', false, 'oyuncular', v_sonuc);
end $$;
revoke all on sticky.puanli_oyunlar from public, anon, authenticated;
revoke execute on function sticky.puanli_sonuc_yaz(uuid, text, jsonb, text[]) from public, anon, authenticated;
grant execute on function sticky.puanli_sonuc_yaz(uuid, text, jsonb, text[]) to service_role;

-- Bu oyundan sil: puanlı oyun kayıtlarındaki kimlik de gider.
create or replace function sticky.oyuncu_verisini_sil(u uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from sticky.stats where user_id = u;
  delete from sticky.rating_log where user_id = u;
  delete from sticky.rated_pairs where position(u::text in pair) > 0;
  delete from sticky.follows where user_id = u or follows_id = u;
  delete from sticky.puanli_oyunlar where sonuc @> jsonb_build_array(jsonb_build_object('kullanici', u));
end $$;

-- ---------------------------------------------------------------- ST-11
create or replace function sticky.siralama(p_donem text, p_ilk int default 100, p_baslangic timestamptz default null,
                                p_kullanici uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  bas timestamptz := coalesce(p_baslangic, sticky.donem_baslangici(p_donem));
  en_az int := case p_donem when 'gun' then 3 when 'hafta' then 5 when 'ay' then 10 else 10 end;
  -- ST-7: servis rolü (Sticky sunucusu) oyuncunun kimliğini verir; başka çağıranda p_kullanici yok sayılır.
  ben uuid := coalesce(case when auth.role() = 'service_role' then p_kullanici end, auth.uid());
  r jsonb;
begin
  if p_donem not in ('gun', 'hafta', 'ay', 'tum') then raise exception 'donem_gecersiz'; end if;
  p_ilk := least(greatest(p_ilk, 1), 500);
  with s as (
    select x.user_id, x.deger, x.oyun, o.ad
    from (
      select st.user_id, st.rating::numeric as deger, st.rated_games as oyun
      from sticky.stats st where p_donem = 'tum' and st.rated_games >= en_az
      union all
      select l.user_id, sum(l.delta)::numeric, count(*)::int
      from sticky.rating_log l where p_donem <> 'tum' and l.at >= bas
      group by l.user_id having count(*) >= en_az
    ) x
    join ortak.oyuncular o on o.oyun_id = 'sticky' and o.kullanici_id = x.user_id and o.ad is not null
  ),
  sirali as (select s.*, row_number() over (order by deger desc, oyun desc, ad asc) as sira from s)
  select jsonb_build_object(
    'toplam', (select count(*) from sirali),
    'ben', (select jsonb_build_object('sira', sira, 'deger', deger, 'oyun', oyun) from sirali where user_id = ben),
    'satirlar', coalesce((select jsonb_agg(jsonb_build_object('sira', sira, 'ad', ad, 'deger', deger, 'oyun', oyun,
                                                              'ben', coalesce(user_id = ben, false)) order by sira)
                          from sirali where sira <= p_ilk), '[]'::jsonb))
  into r;
  return r;
end $$;

create or replace function sticky.haftalik_odul(p_hafta date default null) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  hafta date := coalesce(p_hafta, (date_trunc('week', now() at time zone 'Europe/Istanbul') - interval '7 days')::date);
  bas timestamptz := hafta::timestamp at time zone 'Europe/Istanbul';
  bit timestamptz := (hafta + 7)::timestamp at time zone 'Europe/Istanbul';
  n integer;
begin
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
