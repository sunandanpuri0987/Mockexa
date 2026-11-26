-- User-initiated permanent account and cloud-data deletion.
-- The caller can delete only the identity represented by auth.uid().
create or replace function public.delete_own_account()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_id uuid := auth.uid();
begin
    if caller_id is null then
        raise exception 'Authentication required';
    end if;

    -- Delete session children explicitly so the workflow remains correct even
    -- if an older project schema lacks ON DELETE CASCADE on these relations.
    delete from public.feedback
      where session_id in (select id from public.sessions where user_id = caller_id);
    delete from public.answers
      where session_id in (select id from public.sessions where user_id = caller_id);
    delete from public.gd_messages
      where session_id in (select id from public.sessions where user_id = caller_id);
    delete from public.sessions where user_id = caller_id;
    delete from public.resume_documents where user_id = caller_id;
    delete from public.profiles where id = caller_id;
    delete from auth.users where id = caller_id;

    return found;
end;
$$;

revoke all on function public.delete_own_account() from public;
grant execute on function public.delete_own_account() to authenticated;
