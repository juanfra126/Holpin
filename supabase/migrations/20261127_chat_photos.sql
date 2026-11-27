-- Holpin: envío de fotos privadas en los chats
-- Ejecutar una sola vez en Supabase > SQL Editor.

alter table public.messages
  add column if not exists image_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-photos',
  'chat-photos',
  false,
  8388608,
  array['image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif']
)
on conflict (id) do update
set public = false,
    file_size_limit = 8388608,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Chat participants can view chat photos" on storage.objects;
create policy "Chat participants can view chat photos"
on storage.objects for select
to authenticated
using (
  bucket_id = 'chat-photos'
  and exists (
    select 1
    from public.messages m
    where m.image_path = name
      and (m.from_id = auth.uid() or m.to_id = auth.uid())
  )
);

drop policy if exists "Users can upload their own chat photos" on storage.objects;
create policy "Users can upload their own chat photos"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'chat-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Users can delete their own chat photos" on storage.objects;
create policy "Users can delete their own chat photos"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'chat-photos'
  and (storage.foldername(name))[1] = auth.uid()::text
);
