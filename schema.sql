-- ============================================================================
-- PORTAIL DOCUMENTAIRE CABINET/CLIENT — SCHÉMA MVP (Supabase / Postgres)
-- Multi-tenant : un "cabinet" = un tenant. Isolation stricte via RLS.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. CABINETS (tenants)
-- ----------------------------------------------------------------------------
create table public.cabinets (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  slug text unique not null,              -- utilisé dans les URLs / sous-domaines si besoin
  couleur_theme text default '#1e3a5f',    -- personnalisation légère
  logo_url text,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 2. PROFILS UTILISATEURS (étend auth.users de Supabase)
--    role: 'admin_cabinet' | 'collaborateur' | 'client'
-- ----------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  cabinet_id uuid not null references public.cabinets(id) on delete cascade,
  role text not null check (role in ('admin_cabinet', 'collaborateur', 'client')),
  nom_complet text not null,
  email text not null,
  telephone text,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);

create index idx_profiles_cabinet on public.profiles(cabinet_id);

-- ----------------------------------------------------------------------------
-- 3. CLIENTS (le dossier client géré par le cabinet — distinct du profil "client"
--    qui est le compte de connexion ; un client peut avoir plusieurs utilisateurs)
-- ----------------------------------------------------------------------------
create table public.clients (
  id uuid primary key default gen_random_uuid(),
  cabinet_id uuid not null references public.cabinets(id) on delete cascade,
  raison_sociale text not null,
  ninea text,
  rccm text,
  secteur_activite text,
  exercice_comptable_debut int default 1,   -- mois de début d'exercice (1-12)
  actif boolean not null default true,
  created_at timestamptz not null default now()
);

create index idx_clients_cabinet on public.clients(cabinet_id);

-- Lien entre un profil "client" (utilisateur connecté) et le dossier client
create table public.client_users (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  primary key (profile_id, client_id)
);

-- ----------------------------------------------------------------------------
-- 4. ARBORESCENCE DOCUMENTAIRE — catégories fixes (référentiel global)
-- ----------------------------------------------------------------------------
create table public.categories (
  id serial primary key,
  code text unique not null,           -- ex: 'DOSSIER_PERMANENT'
  libelle text not null,
  ordre int not null
);

create table public.sous_categories (
  id serial primary key,
  categorie_id int not null references public.categories(id) on delete cascade,
  code text not null,
  libelle text not null,
  ordre int not null,
  unique(categorie_id, code)
);

-- Référentiel initial (les 8 catégories + sous-dossiers du cahier des charges)
insert into public.categories (code, libelle, ordre) values
  ('DOSSIER_PERMANENT', 'Dossier permanent', 1),
  ('FACTURES_ACHAT', 'Factures d''achat', 2),
  ('FACTURES_VENTE', 'Factures de vente / Prestations de services', 3),
  ('PIECES_CAISSE', 'Pièces de caisse', 4),
  ('RELEVES_BANCAIRES', 'Relevés bancaires', 5),
  ('PAIE_RH', 'Paie et ressources humaines', 6),
  ('FISCALITE', 'Fiscalité', 7),
  ('AUTRES', 'Autres documents', 8);

insert into public.sous_categories (categorie_id, code, libelle, ordre)
select c.id, v.code, v.libelle, v.ordre from public.categories c
join (values
  ('DOSSIER_PERMANENT','NINEA_RCCM','NINEA / RCCM',1),
  ('DOSSIER_PERMANENT','STATUTS','Statuts',2),
  ('DOSSIER_PERMANENT','BAIL','Contrat de bail',3),
  ('DOSSIER_PERMANENT','PIECE_IDENTITE','Pièce d''identité du dirigeant',4),
  ('DOSSIER_PERMANENT','ATTESTATIONS','Attestation IPRES / CSS / IPM',5),
  ('DOSSIER_PERMANENT','CONTRATS_IMPORTANTS','Contrats importants',6),
  ('DOSSIER_PERMANENT','PROCES_VERBAUX','Procès-verbaux',7),
  ('DOSSIER_PERMANENT','AGREMENTS','Agréments et autorisations',8),
  ('FACTURES_ACHAT','FOURNISSEURS','Fournisseurs',1),
  ('FACTURES_ACHAT','IMPORTATIONS_NDF','Importations / Notes de frais',2),
  ('FACTURES_ACHAT','AVOIRS_FOURNISSEURS','Avoirs fournisseurs',3),
  ('FACTURES_VENTE','FACTURES_EMISES','Factures émises',1),
  ('FACTURES_VENTE','AVOIRS_CLIENTS','Avoirs clients',2),
  ('FACTURES_VENTE','CONTRATS_PRESTATION','Contrats de prestation',3),
  ('FACTURES_VENTE','BC_BL','Bons de commande / bons de livraison',4),
  ('PIECES_CAISSE','DEPENSES_ESPECES','Dépenses espèces',1),
  ('PIECES_CAISSE','RECETTES_ESPECES','Recettes espèces',2),
  ('PIECES_CAISSE','JUSTIFICATIFS_DIVERS','Justificatifs divers',3),
  ('RELEVES_BANCAIRES','RELEVES_MENSUELS','Relevés mensuels',1),
  ('RELEVES_BANCAIRES','AVIS_DEBIT_CREDIT','Avis de débit/crédit',2),
  ('RELEVES_BANCAIRES','CHEQUIERS','Chéquiers / remises de chèques',3),
  ('PAIE_RH','BULLETINS_SALAIRE','Bulletins de salaire',1),
  ('PAIE_RH','CONTRATS_TRAVAIL','Contrats de travail',2),
  ('PAIE_RH','DECLARATIONS_SOCIALES','Déclarations sociales',3),
  ('PAIE_RH','CONGES','Congés',4),
  ('PAIE_RH','RELEVES_PRESENCE','Relevés de présence',5),
  ('FISCALITE','DECLARATIONS_TVA','Déclarations TVA',1),
  ('FISCALITE','IS','Impôt sur les sociétés',2),
  ('FISCALITE','RETENUES_SOURCE','Retenues à la source',3),
  ('FISCALITE','QUITUS_FISCAUX','Quitus fiscaux',4),
  ('AUTRES','CORRESPONDANCES','Correspondances',1),
  ('AUTRES','RAPPORTS','Rapports',2),
  ('AUTRES','DOCUMENTS_EXCEPTIONNELS','Documents exceptionnels',3)
) as v(cat_code, code, libelle, ordre) on c.code = v.cat_code;

-- ----------------------------------------------------------------------------
-- 5. DOCUMENTS
-- ----------------------------------------------------------------------------
create table public.documents (
  id uuid primary key default gen_random_uuid(),
  cabinet_id uuid not null references public.cabinets(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  sous_categorie_id int not null references public.sous_categories(id),
  exercice int not null,                 -- année d'exercice comptable
  mois int,                              -- mois concerné (optionnel selon catégorie)
  nom_fichier_original text not null,
  nom_fichier_stockage text not null,    -- chemin dans Supabase Storage
  taille_octets bigint,
  type_mime text,
  hash_sha256 text,                      -- intégrité (utile aussi en Phase 2 pour Drive)
  statut text not null default 'recu' check (statut in ('recu','manquant','a_completer','valide','rejete')),
  depose_par uuid references public.profiles(id),
  valide_par uuid references public.profiles(id),
  valide_le timestamptz,
  created_at timestamptz not null default now()
);

create index idx_documents_client on public.documents(client_id);
create index idx_documents_cabinet on public.documents(cabinet_id);
create index idx_documents_statut on public.documents(statut);

-- ----------------------------------------------------------------------------
-- 6. COMMENTAIRES / DEMANDES liés à un document
-- ----------------------------------------------------------------------------
create table public.commentaires (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete cascade,
  auteur_id uuid not null references public.profiles(id),
  contenu text not null,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 7. NOTIFICATIONS
-- ----------------------------------------------------------------------------
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  destinataire_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,                    -- 'nouveau_document' | 'demande' | 'validation' | 'rejet'
  document_id uuid references public.documents(id) on delete cascade,
  message text not null,
  lu boolean not null default false,
  created_at timestamptz not null default now()
);

create index idx_notifications_destinataire on public.notifications(destinataire_id, lu);

-- ----------------------------------------------------------------------------
-- 8. JOURNAL D'ACTIVITÉ (connexions, téléchargements)
-- ----------------------------------------------------------------------------
create table public.journal_activite (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  cabinet_id uuid not null references public.cabinets(id) on delete cascade,
  action text not null,                  -- 'connexion' | 'telechargement' | 'depot' | 'validation' ...
  document_id uuid references public.documents(id) on delete set null,
  ip_adresse text,
  created_at timestamptz not null default now()
);

create index idx_journal_cabinet on public.journal_activite(cabinet_id, created_at desc);

-- ============================================================================
-- HELPERS SECURITY DEFINER — évite la récursion RLS (cf. bug rencontré sur Sunu Paie)
-- ============================================================================

create or replace function public.current_cabinet_id()
returns uuid
language sql
security definer
stable
as $$
  select cabinet_id from public.profiles where id = auth.uid()
$$;

create or replace function public.current_role()
returns text
language sql
security definer
stable
as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_client_of(p_client_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.client_users
    where profile_id = auth.uid() and client_id = p_client_id
  )
$$;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

alter table public.cabinets enable row level security;
alter table public.profiles enable row level security;
alter table public.clients enable row level security;
alter table public.client_users enable row level security;
alter table public.documents enable row level security;
alter table public.commentaires enable row level security;
alter table public.notifications enable row level security;
alter table public.journal_activite enable row level security;

-- Profiles : chacun voit les profils de son propre cabinet
create policy profiles_select on public.profiles for select
  using (cabinet_id = public.current_cabinet_id());

create policy profiles_update_self on public.profiles for update
  using (id = auth.uid());

-- Clients : cabinet voit tous ses clients ; un user client ne voit que son propre dossier
create policy clients_select_cabinet on public.clients for select
  using (
    cabinet_id = public.current_cabinet_id()
    and (
      public.current_role() in ('admin_cabinet','collaborateur')
      or public.is_client_of(id)
    )
  );

create policy clients_insert_cabinet on public.clients for insert
  with check (
    cabinet_id = public.current_cabinet_id()
    and public.current_role() in ('admin_cabinet','collaborateur')
  );

create policy clients_update_cabinet on public.clients for update
  using (
    cabinet_id = public.current_cabinet_id()
    and public.current_role() in ('admin_cabinet','collaborateur')
  );

-- Documents : cabinet voit tout ; client ne voit que ses propres documents
create policy documents_select on public.documents for select
  using (
    cabinet_id = public.current_cabinet_id()
    and (
      public.current_role() in ('admin_cabinet','collaborateur')
      or public.is_client_of(client_id)
    )
  );

create policy documents_insert on public.documents for insert
  with check (
    cabinet_id = public.current_cabinet_id()
    and (
      public.current_role() in ('admin_cabinet','collaborateur')
      or public.is_client_of(client_id)
    )
  );

-- Seul le cabinet peut changer le statut (valider/rejeter)
create policy documents_update_cabinet on public.documents for update
  using (
    cabinet_id = public.current_cabinet_id()
    and public.current_role() in ('admin_cabinet','collaborateur')
  );

-- Commentaires : visibles par cabinet + client concerné (via le document)
create policy commentaires_select on public.commentaires for select
  using (
    exists (
      select 1 from public.documents d
      where d.id = document_id
      and d.cabinet_id = public.current_cabinet_id()
      and (
        public.current_role() in ('admin_cabinet','collaborateur')
        or public.is_client_of(d.client_id)
      )
    )
  );

create policy commentaires_insert on public.commentaires for insert
  with check (
    exists (
      select 1 from public.documents d
      where d.id = document_id
      and d.cabinet_id = public.current_cabinet_id()
      and (
        public.current_role() in ('admin_cabinet','collaborateur')
        or public.is_client_of(d.client_id)
      )
    )
  );

-- Notifications : chacun voit les siennes
create policy notifications_select on public.notifications for select
  using (destinataire_id = auth.uid());

create policy notifications_update on public.notifications for update
  using (destinataire_id = auth.uid());

-- Journal : réservé au cabinet (lecture), écriture par tous les profils authentifiés du tenant
create policy journal_select on public.journal_activite for select
  using (
    cabinet_id = public.current_cabinet_id()
    and public.current_role() in ('admin_cabinet','collaborateur')
  );

create policy journal_insert on public.journal_activite for insert
  with check (cabinet_id = public.current_cabinet_id());

-- Cabinets : un profil ne voit que son propre cabinet
create policy cabinets_select on public.cabinets for select
  using (id = public.current_cabinet_id());

-- ============================================================================
-- STORAGE (à créer côté Supabase Storage) :
--   bucket "documents" privé, chemin conseillé :
--   {cabinet_id}/{client_id}/{sous_categorie_code}/{exercice}/{nom_fichier_stockage}
--   Policies storage à répliquer sur le même principe que ci-dessus.
-- ============================================================================
