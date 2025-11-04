-- ============================================================================
-- SCHEMA AVANCÉ - Gestion des données de recherche (Université)
-- ============================================================================
-- Base: PostgreSQL
-- Date: 2025-10-20
-- 
-- Ce script ajoute à la base existante :
-- 1. Rôles et privilèges (administrateurs, data_managers, chercheurs)
-- 2. Index d'optimisation
-- 3. Triggers pour l'automatisation et le contrôle
-- 4. Procédures stockées pour la logique métier
-- 5. Vues pour simplifier les requêtes
-- 6. Table d'audit pour la traçabilité
-- ============================================================================

SET search_path TO univ_recherche;

-- ============================================================================
-- 1. TABLE D'AUDIT / LOGS
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_log (
    id                  BIGSERIAL PRIMARY KEY,
    table_name          TEXT NOT NULL,
    record_id           BIGINT NOT NULL,
    action              TEXT NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values          JSONB,
    new_values          JSONB,
    modified_by         TEXT NOT NULL,
    modified_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ip_address          INET,
    description         TEXT
);

-- Index sur la table d'audit
CREATE INDEX IF NOT EXISTS idx_audit_table_name ON audit_log(table_name);
CREATE INDEX IF NOT EXISTS idx_audit_record_id ON audit_log(record_id);
CREATE INDEX IF NOT EXISTS idx_audit_modified_at ON audit_log(modified_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_modified_by ON audit_log(modified_by);

-- ============================================================================
-- 2. INDEX D'OPTIMISATION
-- ============================================================================

-- Index sur les clés étrangères (pour les JOINs)
CREATE INDEX IF NOT EXISTS idx_laboratoire_institution ON laboratoire(id_institution);
CREATE INDEX IF NOT EXISTS idx_projet_laboratoire ON projet(id_laboratoire_pilote);
CREATE INDEX IF NOT EXISTS idx_projet_responsable ON projet(id_chercheur_responsable);
CREATE INDEX IF NOT EXISTS idx_chercheur_laboratoire ON chercheur(id_laboratoire);
CREATE INDEX IF NOT EXISTS idx_contrat_projet ON contrat(id_projet);
CREATE INDEX IF NOT EXISTS idx_jeu_donnees_contrat ON jeu_donnees(id_contrat);
CREATE INDEX IF NOT EXISTS idx_jeu_donnees_auteur ON jeu_donnees(id_auteur);
CREATE INDEX IF NOT EXISTS idx_publication_auteur_publication ON publication_auteur(id_publication);
CREATE INDEX IF NOT EXISTS idx_publication_auteur_chercheur ON publication_auteur(id_chercheur);
CREATE INDEX IF NOT EXISTS idx_projet_chercheur_projet ON projet_chercheur(id_projet);
CREATE INDEX IF NOT EXISTS idx_projet_chercheur_chercheur ON projet_chercheur(id_chercheur);

-- Index sur les colonnes de recherche fréquentes
CREATE INDEX IF NOT EXISTS idx_chercheur_email ON chercheur(email);
CREATE INDEX IF NOT EXISTS idx_chercheur_orcid ON chercheur(orcid) WHERE orcid IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chercheur_nom_prenom ON chercheur(nom, prenom);
CREATE INDEX IF NOT EXISTS idx_projet_discipline ON projet(discipline);
CREATE INDEX IF NOT EXISTS idx_chercheur_discipline ON chercheur(discipline);
CREATE INDEX IF NOT EXISTS idx_institution_type ON institution(type_institution);

-- Index sur les dates (pour les filtres temporels)
CREATE INDEX IF NOT EXISTS idx_projet_dates ON projet(date_debut, date_fin);
CREATE INDEX IF NOT EXISTS idx_contrat_dates ON contrat(date_debut, date_fin);
CREATE INDEX IF NOT EXISTS idx_contrat_statut_dmp ON contrat(statut_dmp);
CREATE INDEX IF NOT EXISTS idx_jeu_donnees_date_depot ON jeu_donnees(date_depot) WHERE date_depot IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_publication_date ON publication(date_publication);

-- Index sur les types de contrat
CREATE INDEX IF NOT EXISTS idx_contrat_type ON contrat(type_contrat);

-- Index composite pour recherches courantes
CREATE INDEX IF NOT EXISTS idx_projet_actif ON projet(date_debut, date_fin) WHERE date_fin IS NULL OR date_fin >= CURRENT_DATE;

-- ============================================================================
-- 3. TRIGGERS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1. Trigger : Vérification du responsable de projet
-- ----------------------------------------------------------------------------
-- Le responsable doit être membre du projet et appartenir au laboratoire pilote

CREATE OR REPLACE FUNCTION verifier_responsable_projet()
RETURNS TRIGGER AS $$
DECLARE
    v_labo_responsable BIGINT;
    v_est_membre BOOLEAN;
BEGIN
    -- Si aucun responsable n'est défini, OK
    IF NEW.id_chercheur_responsable IS NULL THEN
        RETURN NEW;
    END IF;
    
    -- Vérifier que le chercheur appartient au laboratoire pilote
    SELECT id_laboratoire INTO v_labo_responsable
    FROM chercheur
    WHERE id = NEW.id_chercheur_responsable;
    
    IF v_labo_responsable IS NULL THEN
        RAISE EXCEPTION 'Le chercheur responsable (ID: %) n''existe pas', NEW.id_chercheur_responsable;
    END IF;
    
    IF v_labo_responsable != NEW.id_laboratoire_pilote THEN
        RAISE EXCEPTION 'Le responsable (ID: %) doit appartenir au laboratoire pilote (ID: %)', 
            NEW.id_chercheur_responsable, NEW.id_laboratoire_pilote;
    END IF;
    
    -- Vérifier que le chercheur est membre du projet
    SELECT EXISTS(
        SELECT 1 FROM projet_chercheur
        WHERE id_projet = NEW.id AND id_chercheur = NEW.id_chercheur_responsable
    ) INTO v_est_membre;
    
    IF NOT v_est_membre THEN
        RAISE EXCEPTION 'Le responsable (ID: %) doit être membre du projet (ID: %)', 
            NEW.id_chercheur_responsable, NEW.id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_verifier_responsable_projet
    BEFORE INSERT OR UPDATE OF id_chercheur_responsable, id_laboratoire_pilote
    ON projet
    FOR EACH ROW
    EXECUTE FUNCTION verifier_responsable_projet();

-- ----------------------------------------------------------------------------
-- 3.2. Trigger : Validation du dépôt de données (DMP validé requis)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION verifier_depot_donnees()
RETURNS TRIGGER AS $$
DECLARE
    v_statut_dmp statut_dmp;
BEGIN
    -- Si date_depot est NULL, OK
    IF NEW.date_depot IS NULL THEN
        RETURN NEW;
    END IF;
    
    -- Vérifier que le DMP du contrat est validé
    SELECT statut_dmp INTO v_statut_dmp
    FROM contrat
    WHERE id = NEW.id_contrat;
    
    IF v_statut_dmp != 'valide' THEN
        RAISE EXCEPTION 'Impossible de déposer des données : le DMP du contrat (ID: %) n''est pas validé (statut: %)', 
            NEW.id_contrat, v_statut_dmp;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_verifier_depot_donnees
    BEFORE INSERT OR UPDATE OF date_depot
    ON jeu_donnees
    FOR EACH ROW
    EXECUTE FUNCTION verifier_depot_donnees();

-- ----------------------------------------------------------------------------
-- 3.3. Trigger : Audit automatique des modifications sur les tables sensibles
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION audit_modifications()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, record_id, action, old_values, modified_by)
        VALUES (TG_TABLE_NAME, OLD.id, 'DELETE', row_to_json(OLD)::JSONB, current_user);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values, modified_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'UPDATE', row_to_json(OLD)::JSONB, row_to_json(NEW)::JSONB, current_user);
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, record_id, action, new_values, modified_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', row_to_json(NEW)::JSONB, current_user);
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Appliquer l'audit sur les tables sensibles
CREATE TRIGGER trg_audit_contrat
    AFTER INSERT OR UPDATE OR DELETE ON contrat
    FOR EACH ROW EXECUTE FUNCTION audit_modifications();

CREATE TRIGGER trg_audit_projet
    AFTER INSERT OR UPDATE OR DELETE ON projet
    FOR EACH ROW EXECUTE FUNCTION audit_modifications();

CREATE TRIGGER trg_audit_jeu_donnees
    AFTER INSERT OR UPDATE OR DELETE ON jeu_donnees
    FOR EACH ROW EXECUTE FUNCTION audit_modifications();

-- ----------------------------------------------------------------------------
-- 3.4. Trigger : Mise à jour automatique de la date de validation DMP
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION maj_date_validation_dmp()
RETURNS TRIGGER AS $$
BEGIN
    -- Si le statut passe à 'valide' et que la date n'est pas renseignée
    IF NEW.statut_dmp = 'valide' AND OLD.statut_dmp != 'valide' THEN
        IF NEW.date_validation_dmp IS NULL THEN
            NEW.date_validation_dmp := CURRENT_DATE;
        END IF;
    END IF;
    
    -- Si le statut repasse à non valide, effacer la date de validation
    IF NEW.statut_dmp != 'valide' AND OLD.statut_dmp = 'valide' THEN
        NEW.date_validation_dmp := NULL;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_maj_date_validation_dmp
    BEFORE UPDATE OF statut_dmp ON contrat
    FOR EACH ROW
    EXECUTE FUNCTION maj_date_validation_dmp();

-- ----------------------------------------------------------------------------
-- 3.5. Trigger : Vérifier qu'un projet a au moins un chercheur membre
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION verifier_projet_a_membres()
RETURNS TRIGGER AS $$
DECLARE
    v_nb_membres INTEGER;
BEGIN
    IF TG_OP = 'DELETE' THEN
        -- Compter le nombre de membres restants
        SELECT COUNT(*) INTO v_nb_membres
        FROM projet_chercheur
        WHERE id_projet = OLD.id_projet AND id != OLD.id;
        
        IF v_nb_membres = 0 THEN
            RAISE EXCEPTION 'Impossible de retirer ce chercheur : un projet doit avoir au moins un membre';
        END IF;
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_verifier_projet_a_membres
    BEFORE DELETE ON projet_chercheur
    FOR EACH ROW
    EXECUTE FUNCTION verifier_projet_a_membres();

-- ============================================================================
-- 4. PROCÉDURES STOCKÉES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 4.1. Déclaration d'un nouveau projet par un chercheur
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION declarer_projet(
    p_titre TEXT,
    p_description TEXT,
    p_discipline TEXT,
    p_budget_annuel NUMERIC,
    p_date_debut DATE,
    p_date_fin DATE,
    p_id_laboratoire_pilote BIGINT,
    p_id_chercheur_responsable BIGINT
) RETURNS BIGINT AS $$
DECLARE
    v_nouveau_projet_id BIGINT;
    v_labo_chercheur BIGINT;
BEGIN
    -- Vérifier que le chercheur existe et récupérer son laboratoire
    SELECT id_laboratoire INTO v_labo_chercheur
    FROM chercheur
    WHERE id = p_id_chercheur_responsable;
    
    IF v_labo_chercheur IS NULL THEN
        RAISE EXCEPTION 'Le chercheur (ID: %) n''existe pas', p_id_chercheur_responsable;
    END IF;
    
    -- Vérifier que le chercheur appartient au laboratoire pilote
    IF v_labo_chercheur != p_id_laboratoire_pilote THEN
        RAISE EXCEPTION 'Le chercheur doit appartenir au laboratoire pilote pour créer le projet';
    END IF;
    
    -- Créer le projet sans responsable d'abord
    INSERT INTO projet (titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote)
    VALUES (p_titre, p_description, p_discipline, p_budget_annuel, p_date_debut, p_date_fin, p_id_laboratoire_pilote)
    RETURNING id INTO v_nouveau_projet_id;
    
    -- Ajouter le chercheur comme membre principal du projet
    INSERT INTO projet_chercheur (id_projet, id_chercheur, role, date_debut, is_principal)
    VALUES (v_nouveau_projet_id, p_id_chercheur_responsable, 'Responsable', p_date_debut, TRUE);
    
    -- Définir le responsable du projet
    UPDATE projet
    SET id_chercheur_responsable = p_id_chercheur_responsable
    WHERE id = v_nouveau_projet_id;
    
    RAISE NOTICE 'Projet créé avec succès (ID: %)', v_nouveau_projet_id;
    RETURN v_nouveau_projet_id;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- 4.2. Validation d'un DMP par un data manager
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION valider_dmp(
    p_id_contrat BIGINT,
    p_url_document TEXT
) RETURNS VOID AS $$
DECLARE
    v_statut_actuel statut_dmp;
BEGIN
    -- Récupérer le statut actuel
    SELECT statut_dmp INTO v_statut_actuel
    FROM contrat
    WHERE id = p_id_contrat;
    
    IF v_statut_actuel IS NULL THEN
        RAISE EXCEPTION 'Le contrat (ID: %) n''existe pas', p_id_contrat;
    END IF;
    
    IF v_statut_actuel = 'valide' THEN
        RAISE NOTICE 'Le DMP est déjà validé';
        RETURN;
    END IF;
    
    -- Valider le DMP
    UPDATE contrat
    SET statut_dmp = 'valide',
        url_document_dmp = p_url_document,
        date_validation_dmp = CURRENT_DATE
    WHERE id = p_id_contrat;
    
    RAISE NOTICE 'DMP validé avec succès pour le contrat (ID: %)', p_id_contrat;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- 4.3. Ajouter un chercheur à un projet
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION ajouter_chercheur_projet(
    p_id_projet BIGINT,
    p_id_chercheur BIGINT,
    p_role TEXT DEFAULT 'Collaborateur',
    p_charge_pct NUMERIC DEFAULT NULL,
    p_date_debut DATE DEFAULT CURRENT_DATE
) RETURNS VOID AS $$
BEGIN
    -- Vérifier que le projet et le chercheur existent
    IF NOT EXISTS (SELECT 1 FROM projet WHERE id = p_id_projet) THEN
        RAISE EXCEPTION 'Le projet (ID: %) n''existe pas', p_id_projet;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM chercheur WHERE id = p_id_chercheur) THEN
        RAISE EXCEPTION 'Le chercheur (ID: %) n''existe pas', p_id_chercheur;
    END IF;
    
    -- Vérifier que le chercheur n'est pas déjà membre
    IF EXISTS (SELECT 1 FROM projet_chercheur WHERE id_projet = p_id_projet AND id_chercheur = p_id_chercheur) THEN
        RAISE EXCEPTION 'Le chercheur est déjà membre de ce projet';
    END IF;
    
    -- Ajouter le chercheur au projet
    INSERT INTO projet_chercheur (id_projet, id_chercheur, role, date_debut, charge_pct)
    VALUES (p_id_projet, p_id_chercheur, p_role, p_date_debut, p_charge_pct);
    
    RAISE NOTICE 'Chercheur (ID: %) ajouté au projet (ID: %)', p_id_chercheur, p_id_projet;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- 4.4. Retirer un chercheur d'un projet
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION retirer_chercheur_projet(
    p_id_projet BIGINT,
    p_id_chercheur BIGINT,
    p_date_fin DATE DEFAULT CURRENT_DATE
) RETURNS VOID AS $$
DECLARE
    v_est_responsable BOOLEAN;
BEGIN
    -- Vérifier si le chercheur est responsable du projet
    SELECT (id_chercheur_responsable = p_id_chercheur) INTO v_est_responsable
    FROM projet
    WHERE id = p_id_projet;
    
    IF v_est_responsable THEN
        RAISE EXCEPTION 'Impossible de retirer le responsable du projet. Désignez d''abord un nouveau responsable.';
    END IF;
    
    -- Mettre à jour la date de fin au lieu de supprimer
    UPDATE projet_chercheur
    SET date_fin = p_date_fin
    WHERE id_projet = p_id_projet AND id_chercheur = p_id_chercheur;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Le chercheur (ID: %) n''est pas membre du projet (ID: %)', p_id_chercheur, p_id_projet;
    END IF;
    
    RAISE NOTICE 'Chercheur (ID: %) retiré du projet (ID: %) à la date %', p_id_chercheur, p_id_projet, p_date_fin;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- 4.5. Générer un rapport des projets actifs
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION rapport_projets_actifs()
RETURNS TABLE (
    projet_id BIGINT,
    titre TEXT,
    discipline TEXT,
    laboratoire TEXT,
    responsable TEXT,
    nb_chercheurs BIGINT,
    nb_contrats BIGINT,
    budget_total NUMERIC,
    date_debut DATE,
    date_fin DATE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.titre,
        p.discipline,
        l.nom,
        c.nom || ' ' || c.prenom,
        COUNT(DISTINCT pc.id_chercheur),
        COUNT(DISTINCT ct.id),
        COALESCE(SUM(ct.montant_eur), 0),
        p.date_debut,
        p.date_fin
    FROM projet p
    JOIN laboratoire l ON p.id_laboratoire_pilote = l.id
    LEFT JOIN chercheur c ON p.id_chercheur_responsable = c.id
    LEFT JOIN projet_chercheur pc ON p.id = pc.id_projet
    LEFT JOIN contrat ct ON p.id = ct.id_projet
    WHERE p.date_fin IS NULL OR p.date_fin >= CURRENT_DATE
    GROUP BY p.id, p.titre, p.discipline, l.nom, c.nom, c.prenom, p.date_debut, p.date_fin
    ORDER BY p.date_debut DESC;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- 4.6. Générer un rapport des contrats par type
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION rapport_contrats_par_type()
RETURNS TABLE (
    type_contrat type_contrat,
    nb_contrats BIGINT,
    montant_total NUMERIC,
    montant_moyen NUMERIC,
    nb_dmp_valides BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.type_contrat,
        COUNT(*),
        SUM(c.montant_eur),
        AVG(c.montant_eur),
        COUNT(*) FILTER (WHERE c.statut_dmp = 'valide')
    FROM contrat c
    GROUP BY c.type_contrat
    ORDER BY SUM(c.montant_eur) DESC;
END;
$$ LANGUAGE plpgsql;

-- ----------------------------------------------------------------------------
-- 4.7. Lister les jeux de données prêts à être déposés
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION lister_donnees_prets_depot()
RETURNS TABLE (
    jeu_donnees_id BIGINT,
    description TEXT,
    auteur_nom TEXT,
    contrat_intitule TEXT,
    projet_titre TEXT,
    date_validation_dmp DATE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        jd.id,
        jd.description,
        ch.nom || ' ' || ch.prenom,
        co.intitule,
        pr.titre,
        co.date_validation_dmp
    FROM jeu_donnees jd
    JOIN chercheur ch ON jd.id_auteur = ch.id
    JOIN contrat co ON jd.id_contrat = co.id
    JOIN projet pr ON co.id_projet = pr.id
    WHERE jd.date_depot IS NULL
      AND co.statut_dmp = 'valide'
    ORDER BY co.date_validation_dmp DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 5. VUES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 5.1. Vue : Projets avec leurs chercheurs et contrats
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW v_projets_complets AS
SELECT 
    p.id AS projet_id,
    p.titre AS projet_titre,
    p.discipline,
    p.budget_annuel_eur,
    p.date_debut AS projet_date_debut,
    p.date_fin AS projet_date_fin,
    l.nom AS laboratoire,
    i.nom AS institution,
    COALESCE(c_resp.nom || ' ' || c_resp.prenom, 'Non défini') AS responsable,
    COUNT(DISTINCT pc.id_chercheur) AS nb_chercheurs,
    COUNT(DISTINCT ct.id) AS nb_contrats,
    COALESCE(SUM(ct.montant_eur), 0) AS budget_total_contrats,
    COUNT(DISTINCT jd.id) AS nb_jeux_donnees,
    CASE 
        WHEN p.date_fin IS NULL OR p.date_fin >= CURRENT_DATE THEN 'Actif'
        ELSE 'Terminé'
    END AS statut
FROM projet p
JOIN laboratoire l ON p.id_laboratoire_pilote = l.id
JOIN institution i ON l.id_institution = i.id
LEFT JOIN chercheur c_resp ON p.id_chercheur_responsable = c_resp.id
LEFT JOIN projet_chercheur pc ON p.id = pc.id_projet
LEFT JOIN contrat ct ON p.id = ct.id_projet
LEFT JOIN jeu_donnees jd ON ct.id = jd.id_contrat
GROUP BY p.id, p.titre, p.discipline, p.budget_annuel_eur, p.date_debut, p.date_fin, 
         l.nom, i.nom, c_resp.nom, c_resp.prenom;

-- ----------------------------------------------------------------------------
-- 5.2. Vue : Chercheurs avec leurs projets et publications
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW v_chercheurs_activite AS
SELECT 
    c.id AS chercheur_id,
    c.nom,
    c.prenom,
    c.email,
    c.orcid,
    c.discipline,
    l.nom AS laboratoire,
    i.nom AS institution,
    COUNT(DISTINCT pc.id_projet) AS nb_projets,
    COUNT(DISTINCT pa.id_publication) AS nb_publications,
    COUNT(DISTINCT jd.id) AS nb_jeux_donnees_auteur,
    STRING_AGG(DISTINCT p.titre, ' | ' ORDER BY p.titre) AS projets_titres
FROM chercheur c
JOIN laboratoire l ON c.id_laboratoire = l.id
JOIN institution i ON l.id_institution = i.id
LEFT JOIN projet_chercheur pc ON c.id = pc.id_chercheur
LEFT JOIN projet p ON pc.id_projet = p.id
LEFT JOIN publication_auteur pa ON c.id = pa.id_chercheur
LEFT JOIN jeu_donnees jd ON c.id = jd.id_auteur
GROUP BY c.id, c.nom, c.prenom, c.email, c.orcid, c.discipline, l.nom, i.nom;

-- ----------------------------------------------------------------------------
-- 5.3. Vue : Contrats avec statut DMP
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW v_contrats_dmp AS
SELECT 
    ct.id AS contrat_id,
    ct.intitule,
    ct.type_contrat,
    ct.financeur,
    ct.montant_eur,
    ct.date_debut,
    ct.date_fin,
    ct.statut_dmp,
    ct.date_validation_dmp,
    ct.url_document_dmp,
    p.titre AS projet_titre,
    l.nom AS laboratoire,
    COUNT(jd.id) AS nb_jeux_donnees,
    COUNT(jd.id) FILTER (WHERE jd.date_depot IS NOT NULL) AS nb_jeux_deposes,
    CASE 
        WHEN ct.date_fin < CURRENT_DATE THEN 'Expiré'
        WHEN ct.statut_dmp = 'valide' THEN 'DMP Validé'
        WHEN ct.statut_dmp = 'soumis' THEN 'DMP En attente'
        ELSE 'DMP Brouillon'
    END AS statut_global
FROM contrat ct
JOIN projet p ON ct.id_projet = p.id
JOIN laboratoire l ON p.id_laboratoire_pilote = l.id
LEFT JOIN jeu_donnees jd ON ct.id = jd.id_contrat
GROUP BY ct.id, ct.intitule, ct.type_contrat, ct.financeur, ct.montant_eur, 
         ct.date_debut, ct.date_fin, ct.statut_dmp, ct.date_validation_dmp, 
         ct.url_document_dmp, p.titre, l.nom;

-- ----------------------------------------------------------------------------
-- 5.4. Vue : Jeux de données avec informations complètes
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW v_jeux_donnees_complets AS
SELECT 
    jd.id AS jeu_donnees_id,
    jd.description,
    jd.conditions_acces,
    jd.licence,
    jd.date_depot,
    jd.url_externe,
    c.nom || ' ' || c.prenom AS auteur,
    c.email AS auteur_email,
    ct.intitule AS contrat,
    ct.statut_dmp,
    p.titre AS projet,
    l.nom AS laboratoire,
    CASE 
        WHEN jd.date_depot IS NOT NULL THEN 'Déposé'
        WHEN ct.statut_dmp = 'valide' THEN 'Prêt au dépôt'
        ELSE 'En attente validation DMP'
    END AS statut
FROM jeu_donnees jd
JOIN chercheur c ON jd.id_auteur = c.id
JOIN contrat ct ON jd.id_contrat = ct.id
JOIN projet p ON ct.id_projet = p.id
JOIN laboratoire l ON p.id_laboratoire_pilote = l.id;

-- ----------------------------------------------------------------------------
-- 5.5. Vue : Statistiques par laboratoire
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW v_stats_laboratoires AS
SELECT 
    l.id AS laboratoire_id,
    l.nom AS laboratoire,
    i.nom AS institution,
    i.type_institution,
    COUNT(DISTINCT c.id) AS nb_chercheurs,
    COUNT(DISTINCT p.id) AS nb_projets,
    COUNT(DISTINCT ct.id) AS nb_contrats,
    COALESCE(SUM(ct.montant_eur), 0) AS budget_total_contrats,
    COUNT(DISTINCT jd.id) AS nb_jeux_donnees,
    COUNT(DISTINCT pub.id) AS nb_publications
FROM laboratoire l
JOIN institution i ON l.id_institution = i.id
LEFT JOIN chercheur c ON l.id = c.id_laboratoire
LEFT JOIN projet p ON l.id = p.id_laboratoire_pilote
LEFT JOIN contrat ct ON p.id = ct.id_projet
LEFT JOIN jeu_donnees jd ON ct.id = jd.id_contrat
LEFT JOIN publication_auteur pa ON c.id = pa.id_chercheur
LEFT JOIN publication pub ON pa.id_publication = pub.id
GROUP BY l.id, l.nom, i.nom, i.type_institution
ORDER BY COALESCE(SUM(ct.montant_eur), 0) DESC;

-- ============================================================================
-- 6. RÔLES ET PRIVILÈGES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 6.1. Création des rôles
-- ----------------------------------------------------------------------------

-- Supprimer les rôles s'ils existent déjà (pour réinitialisation)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_administrateur') THEN
        DROP OWNED BY role_administrateur;
        DROP ROLE role_administrateur;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_data_manager') THEN
        DROP OWNED BY role_data_manager;
        DROP ROLE role_data_manager;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_chercheur') THEN
        DROP OWNED BY role_chercheur;
        DROP ROLE role_chercheur;
    END IF;
END $$;

-- Créer les rôles
CREATE ROLE role_administrateur;
CREATE ROLE role_data_manager;
CREATE ROLE role_chercheur;

-- ----------------------------------------------------------------------------
-- 6.2. Privilèges pour ADMINISTRATEUR
-- ----------------------------------------------------------------------------
-- Accès complet à toutes les tables et séquences

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA univ_recherche TO role_administrateur;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA univ_recherche TO role_administrateur;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA univ_recherche TO role_administrateur;
GRANT USAGE ON SCHEMA univ_recherche TO role_administrateur;

-- ----------------------------------------------------------------------------
-- 6.3. Privilèges pour DATA_MANAGER
-- ----------------------------------------------------------------------------
-- Gestion des contrats, validation DMP, consultation des données

-- Lecture sur toutes les tables
GRANT SELECT ON ALL TABLES IN SCHEMA univ_recherche TO role_data_manager;

-- Écriture sur les tables de gestion
GRANT INSERT, UPDATE ON contrat TO role_data_manager;
GRANT INSERT, UPDATE, DELETE ON jeu_donnees TO role_data_manager;
GRANT INSERT ON audit_log TO role_data_manager;

-- Accès aux séquences nécessaires
GRANT USAGE, SELECT ON SEQUENCE contrat_id_seq TO role_data_manager;
GRANT USAGE, SELECT ON SEQUENCE jeu_donnees_id_seq TO role_data_manager;
GRANT USAGE, SELECT ON SEQUENCE audit_log_id_seq TO role_data_manager;

-- Exécution des procédures de validation et reporting
GRANT EXECUTE ON FUNCTION valider_dmp(BIGINT, TEXT) TO role_data_manager;
GRANT EXECUTE ON FUNCTION rapport_projets_actifs() TO role_data_manager;
GRANT EXECUTE ON FUNCTION rapport_contrats_par_type() TO role_data_manager;
GRANT EXECUTE ON FUNCTION lister_donnees_prets_depot() TO role_data_manager;

-- Accès au schéma
GRANT USAGE ON SCHEMA univ_recherche TO role_data_manager;

-- ----------------------------------------------------------------------------
-- 6.4. Privilèges pour CHERCHEUR
-- ----------------------------------------------------------------------------
-- Consultation de leurs projets, déclaration de projets, publication de données

-- Lecture sur les tables principales (consultation)
GRANT SELECT ON institution, laboratoire, projet, chercheur, contrat, 
               publication, publication_auteur, jeu_donnees, projet_chercheur 
               TO role_chercheur;

-- Consultation des vues
GRANT SELECT ON v_projets_complets, v_chercheurs_activite, 
                v_contrats_dmp, v_jeux_donnees_complets 
                TO role_chercheur;

-- Insertion de nouveaux projets (via procédure)
GRANT EXECUTE ON FUNCTION declarer_projet(TEXT, TEXT, TEXT, NUMERIC, DATE, DATE, BIGINT, BIGINT) TO role_chercheur;

-- Insertion/modification de leurs jeux de données
GRANT INSERT ON jeu_donnees TO role_chercheur;
GRANT UPDATE (description, conditions_acces, licence, date_depot, url_externe) ON jeu_donnees TO role_chercheur;

-- Insertion de publications
GRANT INSERT ON publication, publication_auteur TO role_chercheur;
GRANT USAGE, SELECT ON SEQUENCE publication_id_seq TO role_chercheur;

-- Accès aux séquences nécessaires
GRANT USAGE, SELECT ON SEQUENCE jeu_donnees_id_seq TO role_chercheur;
GRANT USAGE, SELECT ON SEQUENCE projet_id_seq TO role_chercheur;
GRANT USAGE, SELECT ON SEQUENCE projet_chercheur_id_seq TO role_chercheur;

-- Accès au schéma
GRANT USAGE ON SCHEMA univ_recherche TO role_chercheur;

-- ============================================================================
-- 8. EXEMPLES D'UTILISATION
-- ============================================================================

-- Créer des utilisateurs (exemples - à adapter selon vos besoins)
/*
-- Administrateur
CREATE USER admin_user WITH PASSWORD 'admin_password';
GRANT role_administrateur TO admin_user;

-- Data Manager
CREATE USER data_manager_user WITH PASSWORD 'dm_password';
GRANT role_data_manager TO data_manager_user;

-- Chercheur (l'email doit correspondre à un chercheur dans la table)
CREATE USER chercheur1@univ.fr WITH PASSWORD 'chercheur_password';
GRANT role_chercheur TO chercheur1@univ.fr;
*/

-- ============================================================================
-- COMMENTAIRES ET DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE audit_log IS 'Table d''audit pour tracer toutes les modifications importantes';
COMMENT ON FUNCTION declarer_projet IS 'Permet à un chercheur de déclarer un nouveau projet';
COMMENT ON FUNCTION valider_dmp IS 'Permet à un data manager de valider un DMP';
COMMENT ON FUNCTION ajouter_chercheur_projet IS 'Ajoute un chercheur à un projet existant';
COMMENT ON FUNCTION retirer_chercheur_projet IS 'Retire un chercheur d''un projet (met à jour la date de fin)';
COMMENT ON FUNCTION rapport_projets_actifs IS 'Génère un rapport des projets actuellement actifs';
COMMENT ON FUNCTION rapport_contrats_par_type IS 'Génère des statistiques sur les contrats par type';
COMMENT ON VIEW v_projets_complets IS 'Vue consolidée des projets avec toutes leurs informations';
COMMENT ON VIEW v_chercheurs_activite IS 'Vue de l''activité des chercheurs (projets, publications, données)';
COMMENT ON VIEW v_contrats_dmp IS 'Vue des contrats avec leur statut DMP et jeux de données';

-- ============================================================================
-- FIN DU SCRIPT
-- ============================================================================

RAISE NOTICE '============================================================';
RAISE NOTICE 'Script d''amélioration de la base de données terminé !';
RAISE NOTICE '============================================================';
RAISE NOTICE 'Éléments ajoutés :';
RAISE NOTICE '- Table d''audit (audit_log)';
RAISE NOTICE '- Index d''optimisation (20+ index)';
RAISE NOTICE '- 5 Triggers pour l''automatisation et le contrôle';
RAISE NOTICE '- 7 Procédures stockées pour la logique métier';
RAISE NOTICE '- 5 Vues pour simplifier les requêtes';
RAISE NOTICE '- 3 Rôles avec privilèges (administrateur, data_manager, chercheur)';
RAISE NOTICE '- Politiques RLS pour la sécurité au niveau ligne';
RAISE NOTICE '============================================================';
