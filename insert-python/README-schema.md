# Schéma relationnel – Gestion des données de recherche (PostgreSQL)

Ce dépôt contient un script SQL PostgreSQL avec des noms de tables et colonnes en français pour créer la base de données couvrant: institutions, laboratoires, chercheurs, projets structurants, contrats de financement, publications (métadonnées) et jeux de données (métadonnées).

## Hypothèses et choix de modélisation

- Chaque chercheur appartient à un seul laboratoire (colonne `chercheur.id_laboratoire`).
- Simplification demandée: chaque chercheur est impliqué dans au plus un projet structurant (colonne `chercheur.id_projet`).
- Un projet structurant peut impliquer plusieurs chercheurs et possède un responsable unique (`projet.id_chercheur_responsable`).
- Hypothèse (explicite): le chercheur responsable d’un projet est issu du laboratoire pilote (`projet.id_laboratoire_pilote`). Une contrainte de déclencheur l’impose.
- Un contrat finance exactement un projet; un projet peut avoir plusieurs contrats (`contrat.id_projet`).
- Chaque contrat a un DMP avec statut (`brouillon|soumis|valide`), une date de validation et un lien vers le document (si et seulement si `valide`).
- Les jeux de données sont rattachés à un contrat et à un auteur (chercheur). Le dépôt officiel (champ `date_depot` non NULL) n’est autorisé que si le DMP du contrat est validé.
- Les publications stockent uniquement des métadonnées et la relation N–N auteurs est modélisée par `publication_auteur` avec l’ordre d’auteur (`ordre_auteur`).

## Tables principales (FR)

- `institution(id, nom, type_institution, adresse)` – `type_institution` est un enum: `universite|organisme_recherche|partenaire_prive`.
- `laboratoire(id, nom, id_institution)` – rattachement à une institution.
- `projet(id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable)` – contraintes sur les dates et le budget.
- `chercheur(id, prenom, nom, email, orcid, discipline, id_laboratoire, id_projet)` – email et ORCID uniques.
- `contrat(id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp)` – contraintes dates et DMP.
- `publication(id, titre, doi, date_publication, nb_pages, url_externe)`.
- `publication_auteur(id_publication, id_chercheur, ordre_auteur)` – PK composite, unicité de l’ordre auteur par publication.
- `jeu_donnees(id, id_contrat, description, id_auteur, conditions_acces, licence, date_depot, url_externe)` – trigger DMP sur `date_depot`.

## Contraintes et triggers notables

- `trg_verifier_responsable_projet` (avant INSERT/UPDATE sur `projet`):
  - vérifie que le responsable renseigné est bien affecté au projet (`chercheur.id_projet = projet.id`),
  - vérifie l’appartenance du responsable au laboratoire pilote (hypothèse de conception).
- `trg_verifier_dmp_depot` (avant INSERT/UPDATE sur `jeu_donnees`):
  - refuse une `date_depot` non NULL si le DMP du contrat n’est pas au statut `valide` avec une date de validation.
- `chk_dmp_valide_champs` (CHECK sur `contrat`): impose que `date_validation_dmp` et `url_document_dmp` soient renseignés quand `statut_dmp='valide'`.

## Comment exécuter (Windows / PowerShell)

Pré-requis: disposer d’un serveur PostgreSQL et de l’outil `psql` dans le PATH.

1. Créez (si besoin) une base de données vide, par exemple `univ_recherche`.
2. Exécutez le script SQL.

```powershell
# Exemple: variables
$PGUSER = "postgres"    # à adapter
$PGDB   = "univ_recherche"  # à créer au préalable: createdb -U postgres univ_recherche
$PGHOST = "localhost"
$PGPORT = 5432
$SCRIPT = "schema_univ_recherche_fr.sql"

# Exécution du script
psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDB -f $SCRIPT
```

Astuce: si vous voulez isoler le modèle dans un autre schéma que `univ_recherche`, modifiez `CREATE SCHEMA` et `SET search_path` en tête de script.

## Idées d’enrichissement

- Historiser les statuts de DMP (table `historique_statut_dmp`).
- Ajouter une table `discipline` de référence et FK depuis `projet` et `chercheur`.
- Lier optionnellement `publication` à `projet`.
- Ajouter des rôles dans un projet (ex.: co-responsable, doctorant, postdoc) via une table d’association.

## Fichier à exécuter

- Script SQL (FR): `schema_univ_recherche_fr.sql`
