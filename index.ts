// supabase/functions/create-client-user/index.ts
//
// Déploiement : supabase functions deploy create-client-user
// Cette fonction tourne côté serveur avec la clé service_role (jamais exposée au navigateur).
// Elle est appelée depuis app.html via sb.functions.invoke('create-client-user', {...})
//
// Rôle : un admin_cabinet crée un nouveau dossier client + son compte de connexion en une
// seule opération (auth.users + profiles + clients + client_users), de façon atomique
// et sécurisée (le mot de passe n'est jamais stocké en clair côté cabinet).

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  try {
    // 1. Vérifier que l'appelant est authentifié et est bien admin_cabinet/collaborateur
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Non authentifié." }, 401);
    }

    const callerClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user: caller }, error: callerErr } = await callerClient.auth.getUser();
    if (callerErr || !caller) {
      return json({ error: "Session invalide." }, 401);
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    const { data: callerProfile, error: profileErr } = await admin
      .from("profiles")
      .select("role, cabinet_id")
      .eq("id", caller.id)
      .single();

    if (profileErr || !callerProfile || !["admin_cabinet", "collaborateur"].includes(callerProfile.role)) {
      return json({ error: "Droits insuffisants." }, 403);
    }

    // 2. Lire les paramètres de la requête
    const body = await req.json();
    const { raison_sociale, ninea, rccm, secteur_activite, email, nom_complet, telephone } = body;

    if (!raison_sociale || !email || !nom_complet) {
      return json({ error: "Champs obligatoires manquants (raison_sociale, email, nom_complet)." }, 400);
    }

    // 3. Créer le dossier client (tenant = celui de l'appelant)
    const { data: client, error: clientErr } = await admin
      .from("clients")
      .insert({
        cabinet_id: callerProfile.cabinet_id,
        raison_sociale,
        ninea: ninea ?? null,
        rccm: rccm ?? null,
        secteur_activite: secteur_activite ?? null,
      })
      .select()
      .single();

    if (clientErr) {
      return json({ error: "Erreur lors de la création du dossier client.", details: clientErr.message }, 500);
    }

    // 4. Créer le compte auth (mot de passe temporaire aléatoire, à changer via lien de réinitialisation)
    const tempPassword = crypto.randomUUID();

    const { data: authUser, error: authErr } = await admin.auth.admin.createUser({
      email,
      password: tempPassword,
      email_confirm: true,
    });

    if (authErr || !authUser?.user) {
      // Rollback du dossier client si la création du compte échoue
      await admin.from("clients").delete().eq("id", client.id);
      return json({ error: "Erreur lors de la création du compte utilisateur.", details: authErr?.message }, 500);
    }

    // 5. Créer le profil + lier au client
    const { error: profileInsertErr } = await admin.from("profiles").insert({
      id: authUser.user.id,
      cabinet_id: callerProfile.cabinet_id,
      role: "client",
      nom_complet,
      email,
      telephone: telephone ?? null,
    });

    if (profileInsertErr) {
      await admin.auth.admin.deleteUser(authUser.user.id);
      await admin.from("clients").delete().eq("id", client.id);
      return json({ error: "Erreur lors de la création du profil.", details: profileInsertErr.message }, 500);
    }

    await admin.from("client_users").insert({
      profile_id: authUser.user.id,
      client_id: client.id,
    });

    // 6. Envoyer un lien de définition de mot de passe (le client choisit son propre mot de passe)
    const { error: resetErr } = await admin.auth.resetPasswordForEmail(email);

    return json({
      success: true,
      client_id: client.id,
      user_id: authUser.user.id,
      password_reset_sent: !resetErr,
    });

  } catch (e) {
    return json({ error: "Erreur interne.", details: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
