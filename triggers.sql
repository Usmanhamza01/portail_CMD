-- ============================================================================
-- TRIGGERS — notifications automatiques
-- ============================================================================

-- ---------- 1. Nouveau document déposé par un client -> notifier le cabinet ----------
create or replace function public.notify_nouveau_document()
returns trigger
language plpgsql
security definer
as $$
declare
  v_deposant_role text;
  v_client_nom text;
begin
  select role into v_deposant_role from public.profiles where id = new.depose_par;

  if v_deposant_role = 'client' then
    select raison_sociale into v_client_nom from public.clients where id = new.client_id;

    insert into public.notifications (destinataire_id, type, document_id, message)
    select p.id, 'nouveau_document', new.id,
           v_client_nom || ' a déposé un nouveau document : ' || new.nom_fichier_original
    from public.profiles p
    where p.cabinet_id = new.cabinet_id
      and p.role in ('admin_cabinet', 'collaborateur')
      and p.actif = true;
  end if;

  return new;
end;
$$;

create trigger trg_notify_nouveau_document
after insert on public.documents
for each row execute function public.notify_nouveau_document();

-- ---------- 2. Changement de statut (validé / rejeté) -> notifier le client ----------
create or replace function public.notify_changement_statut()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.statut is distinct from old.statut and new.statut in ('valide', 'rejete') then
    insert into public.notifications (destinataire_id, type, document_id, message)
    select cu.profile_id,
           case when new.statut = 'valide' then 'validation' else 'rejet' end,
           new.id,
           case
             when new.statut = 'valide' then 'Votre document "' || new.nom_fichier_original || '" a été validé.'
             else 'Votre document "' || new.nom_fichier_original || '" a été rejeté. Consultez les commentaires.'
           end
    from public.client_users cu
    where cu.client_id = new.client_id;
  end if;

  return new;
end;
$$;

create trigger trg_notify_changement_statut
after update on public.documents
for each row execute function public.notify_changement_statut();

-- ---------- 3. Nouveau commentaire -> notifier "l'autre côté" ----------
create or replace function public.notify_nouveau_commentaire()
returns trigger
language plpgsql
security definer
as $$
declare
  v_auteur_role text;
  v_doc record;
begin
  select role into v_auteur_role from public.profiles where id = new.auteur_id;
  select * into v_doc from public.documents where id = new.document_id;

  if v_auteur_role in ('admin_cabinet', 'collaborateur') then
    -- notifier le(s) client(s) lié(s) au dossier
    insert into public.notifications (destinataire_id, type, document_id, message)
    select cu.profile_id, 'demande', new.id,
           'Nouveau message du cabinet sur "' || v_doc.nom_fichier_original || '"'
    from public.client_users cu
    where cu.client_id = v_doc.client_id;
  else
    -- notifier le cabinet
    insert into public.notifications (destinataire_id, type, document_id, message)
    select p.id, 'demande', new.id,
           'Nouveau message client sur "' || v_doc.nom_fichier_original || '"'
    from public.profiles p
    where p.cabinet_id = v_doc.cabinet_id
      and p.role in ('admin_cabinet', 'collaborateur')
      and p.actif = true;
  end if;

  return new;
end;
$$;

create trigger trg_notify_nouveau_commentaire
after insert on public.commentaires
for each row execute function public.notify_nouveau_commentaire();
