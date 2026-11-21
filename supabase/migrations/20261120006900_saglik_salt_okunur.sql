-- Sağlık betiği (scripts/saglik.ts) `db query --read-only` ile Supabase'in salt okunur rolüyle bağlanır. isletim_durumu
-- yalnız okur (stable): bu role çağırma izni verilir. Rol yerel yığında yoksa atlanır.
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    grant usage on schema ortak to supabase_read_only_user;
    grant execute on function ortak.isletim_durumu() to supabase_read_only_user;
  end if;
end $$;
