Générateur de données pour le TP1 — schéma `univ_recherche`

Prérequis
- Python 3.8+
- Installer les dépendances:

    pip install -r requirements.txt

Usage

Générer la base SQLite et un fichier SQL d'inserts:

    python generate_data.py --rows 100

Sorties
- `univ_recherche.db` : base SQLite contenant les données générées
- `inserts.sql` : dump SQL SQLite (y compris CREATE TABLE et INSERT)

PostgreSQL

Si vous voulez obtenir un fichier SQL compatible PostgreSQL (INSERTs et réglage des séquences), utilisez l'option `--dialect postgres`. Le script lit la base SQLite générée et écrit `inserts_postgres.sql`.

    python generate_data.py --rows 100 --dialect postgres

Le fichier `inserts_postgres.sql` contient des INSERT INTO univ_recherche.<table> ... et des appels à `setval` pour remettre les séquences.

Notes
- Le script produit un schéma SQLite simplifié compatible avec le script PostgreSQL fourni.
- Les contraintes complexes (CHECK avancés, types ENUM natifs) sont émulated par des TEXT et des règles applicatives dans le script.
