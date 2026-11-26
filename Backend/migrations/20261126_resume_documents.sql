-- Durable per-user Resume Studio data. Run once in the Supabase SQL editor.
create table if not exists public.resume_documents (
    user_id uuid primary key references public.profiles(id) on delete cascade,
    profiles jsonb not null default '[]'::jsonb,
    active_profile_id text,
    updated_at timestamptz not null default now(),
    constraint resume_documents_profiles_array check (jsonb_typeof(profiles) = 'array')
);

alter table public.resume_documents enable row level security;

drop policy if exists "resume_documents_select_own" on public.resume_documents;
create policy "resume_documents_select_own" on public.resume_documents
    for select using (auth.uid() = user_id);

drop policy if exists "resume_documents_insert_own" on public.resume_documents;
create policy "resume_documents_insert_own" on public.resume_documents
    for insert with check (auth.uid() = user_id);

drop policy if exists "resume_documents_update_own" on public.resume_documents;
create policy "resume_documents_update_own" on public.resume_documents
    for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.set_resume_documents_updated_at()
returns trigger language plpgsql security invoker set search_path = public as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists resume_documents_set_updated_at on public.resume_documents;
create trigger resume_documents_set_updated_at
before update on public.resume_documents
for each row execute function public.set_resume_documents_updated_at();
