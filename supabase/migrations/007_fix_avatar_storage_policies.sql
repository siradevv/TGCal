-- Drop old policies
drop policy if exists "Users can upload their own avatar" on storage.objects;
drop policy if exists "Users can update their own avatar" on storage.objects;
drop policy if exists "Anyone can read avatars" on storage.objects;

-- Recreate with simpler path check using split_part
-- Upload path format: {userId}/avatar.jpg

create policy "avatars_insert"
on storage.objects for insert
to authenticated
with check (
    bucket_id = 'avatars'
    and auth.uid()::text = split_part(name, '/', 1)
);

create policy "avatars_update"
on storage.objects for update
to authenticated
using (
    bucket_id = 'avatars'
    and auth.uid()::text = split_part(name, '/', 1)
);

create policy "avatars_delete"
on storage.objects for delete
to authenticated
using (
    bucket_id = 'avatars'
    and auth.uid()::text = split_part(name, '/', 1)
);

create policy "avatars_select"
on storage.objects for select
to public
using (bucket_id = 'avatars');
