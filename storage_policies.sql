-- ============================================================================
-- STORAGE — bucket "documents" (privé)
-- Convention de chemin : {cabinet_id}/{client_id}/{sous_categorie_code}/{exercice}/{fichier}
-- À exécuter APRÈS avoir créé le bucket "documents" (privé) dans Supabase Storage.
-- ============================================================================

-- Le bucket doit être créé en privé (public = false) :
-- insert into storage.buckets (id, name, public) values ('documents', 'documents', false);

-- Helper : extrait le cabinet_id et le client_id à partir du chemin du fichier
-- storage.foldername(name) renvoie un tableau des segments du chemin, ex:
-- {cabinet_id, client_id, sous_categorie_code, exercice, fichier}

create policy "documents_storage_select"
on storage.objects for select
using (
  bucket_id = 'documents'
  and (
    -- Cabinet (admin/collaborateur) : accès à tout son tenant
    (
      public.current_role() in ('admin_cabinet','collaborateur')
      and (storage.foldername(name))[1] = public.current_cabinet_id()::text
    )
    or
    -- Client : uniquement son propre dossier
    (
      public.current_role() = 'client'
      and (storage.foldername(name))[1] = public.current_cabinet_id()::text
      and public.is_client_of(((storage.foldername(name))[2])::uuid)
    )
  )
);

create policy "documents_storage_insert"
on storage.objects for insert
with check (
  bucket_id = 'documents'
  and (
    (
      public.current_role() in ('admin_cabinet','collaborateur')
      and (storage.foldername(name))[1] = public.current_cabinet_id()::text
    )
    or
    (
      public.current_role() = 'client'
      and (storage.foldername(name))[1] = public.current_cabinet_id()::text
      and public.is_client_of(((storage.foldername(name))[2])::uuid)
    )
  )
);

-- Suppression réservée au cabinet (un client ne supprime jamais un document déposé)
create policy "documents_storage_delete"
on storage.objects for delete
using (
  bucket_id = 'documents'
  and public.current_role() in ('admin_cabinet','collaborateur')
  and (storage.foldername(name))[1] = public.current_cabinet_id()::text
);

-- Mise à jour (remplacement de fichier / versioning futur) réservée au cabinet
create policy "documents_storage_update"
on storage.objects for update
using (
  bucket_id = 'documents'
  and public.current_role() in ('admin_cabinet','collaborateur')
  and (storage.foldername(name))[1] = public.current_cabinet_id()::text
);
