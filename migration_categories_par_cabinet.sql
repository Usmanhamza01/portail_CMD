-- ============================================================================
-- MIGRATION — Catégories personnalisables par cabinet
-- À exécuter une seule fois, APRÈS schema.sql / storage_policies.sql / triggers.sql
-- ============================================================================

-- 1. Ajouter cabinet_id (nullable = "modèle global", non-nullable pour un cabinet = ses propres dossiers)
alter table public.categories add column if not exists cabinet_id uuid references public.cabinets(id) on delete cascade;
alter table public.sous_categories add column if not exists cabinet_id uuid references public.cabinets(id) on delete cascade;

-- 2. Marquer les 8 catégories existantes comme "modèle standard" (cabinet_id = null = disponible pour tout le monde comme modèle à importer)
update public.categories set cabinet_id = null where cabinet_id is not null; -- no-op de sécurité si déjà migré

-- 3. Pour CHAQUE cabinet déjà existant, cloner le modèle standard dans ses propres catégories
--    (ainsi les cabinets déjà en place gardent leur arborescence actuelle)
do $$
declare
  v_cabinet record;
  v_cat record;
  v_new_cat_id int;
  v_sub record;
begin
  for v_cabinet in select id from public.cabinets loop
    for v_cat in select * from public.categories where cabinet_id is null order by ordre loop
      insert into public.categories (cabinet_id, code, libelle, ordre)
      values (v_cabinet.id, v_cat.code, v_cat.libelle, v_cat.ordre)
      returning id into v_new_cat_id;

      for v_sub in select * from public.sous_categories where categorie_id = v_cat.id order by ordre loop
        insert into public.sous_categories (cabinet_id, categorie_id, code, libelle, ordre)
        values (v_cabinet.id, v_new_cat_id, v_sub.code, v_sub.libelle, v_sub.ordre);
      end loop;
    end loop;
  end loop;
end $$;

-- 4. Faire pointer les documents existants vers les NOUVELLES sous_categories du bon cabinet
--    (on retrouve la correspondance via le code, qui est resté identique)
update public.documents d
set sous_categorie_id = sc_new.id
from public.sous_categories sc_old
join public.sous_categories sc_new
  on sc_new.code = sc_old.code
  and sc_new.cabinet_id = d.cabinet_id
where d.sous_categorie_id = sc_old.id
  and sc_old.cabinet_id is null;

-- 5. Idem pour les demandes de document déjà créées via la modale "Demander un document"
--    (déjà couvert par la requête ci-dessus car elles sont aussi dans "documents")

-- 6. Rendre cabinet_id obligatoire désormais pour toute NOUVELLE sous-catégorie propre à un cabinet
--    (le modèle standard, lui, garde cabinet_id = null en permanence)
-- Pas de contrainte NOT NULL globale ici : on veut conserver le modèle (cabinet_id null) comme référence importable.

-- 7. Index utiles
create index if not exists idx_categories_cabinet on public.categories(cabinet_id);
create index if not exists idx_sous_categories_cabinet on public.sous_categories(cabinet_id);

-- 8. RLS sur categories / sous_categories : chaque cabinet ne voit que SES catégories + le modèle standard (cabinet_id null)
alter table public.categories enable row level security;
alter table public.sous_categories enable row level security;

drop policy if exists categories_select on public.categories;
create policy categories_select on public.categories for select
  using (cabinet_id is null or cabinet_id = public.current_cabinet_id());

drop policy if exists categories_insert on public.categories;
create policy categories_insert on public.categories for insert
  with check (cabinet_id = public.current_cabinet_id() and public.current_role() in ('admin_cabinet','collaborateur'));

drop policy if exists categories_update on public.categories;
create policy categories_update on public.categories for update
  using (cabinet_id = public.current_cabinet_id() and public.current_role() in ('admin_cabinet','collaborateur'));

drop policy if exists categories_delete on public.categories;
create policy categories_delete on public.categories for delete
  using (cabinet_id = public.current_cabinet_id() and public.current_role() in ('admin_cabinet','collaborateur'));

drop policy if exists sous_categories_select on public.sous_categories;
create policy sous_categories_select on public.sous_categories for select
  using (cabinet_id is null or cabinet_id = public.current_cabinet_id());

drop policy if exists sous_categories_insert on public.sous_categories;
create policy sous_categories_insert on public.sous_categories for insert
  with check (cabinet_id = public.current_cabinet_id() and public.current_role() in ('admin_cabinet','collaborateur'));

drop policy if exists sous_categories_update on public.sous_categories;
create policy sous_categories_update on public.sous_categories for update
  using (cabinet_id = public.current_cabinet_id() and public.current_role() in ('admin_cabinet','collaborateur'));

drop policy if exists sous_categories_delete on public.sous_categories;
create policy sous_categories_delete on public.sous_categories for delete
  using (cabinet_id = public.current_cabinet_id() and public.current_role() in ('admin_cabinet','collaborateur'));
