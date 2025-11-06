#!/usr/bin/env python3
"""
Générateur de données pour le schéma `univ_recherche` (PostgreSQL uniquement).
Produit un fichier `inserts_postgres.sql` contenant les INSERTs.
Usage:
    python generate_data.py --rows 50
Dépendances: Faker
"""
import argparse
import random
from datetime import date, timedelta
from pathlib import Path
from typing import List, Optional
from faker import Faker

INSERTS_PG = Path(__file__).with_name("inserts_postgres.sql")

def _quote_sql(val: Optional[object]) -> str:
    """Retourne une valeur SQL correctement échappée."""
    if val is None:
        return "NULL"
    if isinstance(val, (int, float)):
        return str(val)
    s = str(val)
    s = s.replace("'", "''")
    return f"'{s}'"

def gen_orcid(fake: Faker) -> str:
    parts = ["%04d" % random.randint(0, 9999) for _ in range(4)]
    return "-".join(parts)

def random_date_between(start: date, end: date) -> date:
    delta = (end - start).days
    if delta <= 0:
        return start
    return start + timedelta(days=random.randint(0, delta))

def write_header(f, schema_file: Path) -> None:
    """Écrit l'en-tête du fichier SQL."""
    f.write("-- PostgreSQL dump generated (synthetic data)\nBEGIN;\n")
    if schema_file.exists():
        f.write("-- Schema header from infos/schema_univ_recherche.sql\n")
        f.write(schema_file.read_text(encoding="utf-8"))
        f.write("\n")
    else:
        f.write("CREATE SCHEMA IF NOT EXISTS univ_recherche;\nSET search_path TO univ_recherche;\n\n")

def generate_institutions(f, fake: Faker, count: int) -> List[int]:
    """Génère les institutions et retourne la liste des IDs."""
    types_institution = ["universite", "organisme_recherche", "partenaire_prive"]
    institutions = []
    
    for iid in range(1, count + 1):
        nom = fake.company()
        typ = random.choice(types_institution)
        adresse = fake.address().replace('\n', ', ')
        institutions.append(iid)
        f.write(f"INSERT INTO univ_recherche.institution (id, nom, type_institution, adresse) VALUES ({iid}, {_quote_sql(nom)}, {_quote_sql(typ)}, {_quote_sql(adresse)});\n")
    
    f.write("SELECT setval(pg_get_serial_sequence('univ_recherche.institution','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.institution),0));\n")
    return institutions

def generate_laboratoires(f, fake: Faker, institutions: List[int], count: int) -> List[int]:
    """Génère les laboratoires et retourne la liste des IDs."""
    laboratoires = []
    lab_names_per_institution = {}
    
    for lid in range(1, count + 1):
        id_institution = random.choice(institutions)
        if id_institution not in lab_names_per_institution:
            lab_names_per_institution[id_institution] = set()
        
        # Générer un nom unique pour cette institution
        attempts = 0
        while attempts < 100:
            nom = fake.bs().capitalize() + " Lab"
            if nom not in lab_names_per_institution[id_institution]:
                lab_names_per_institution[id_institution].add(nom)
                break
            attempts += 1
        else:
            # Fallback: ajouter un suffixe unique
            nom = f"{fake.bs().capitalize()} Lab {lid}"
            lab_names_per_institution[id_institution].add(nom)
        
        laboratoires.append(lid)
        f.write(f"INSERT INTO univ_recherche.laboratoire (id, nom, id_institution) VALUES ({lid}, {_quote_sql(nom)}, {id_institution});\n")
    
    f.write("SELECT setval(pg_get_serial_sequence('univ_recherche.laboratoire','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.laboratoire),0));\n")
    return laboratoires

def generate_chercheurs(f, fake: Faker, laboratoires: List[int], count: int) -> List[int]:
    """Génère les chercheurs et retourne la liste des IDs."""
    chercheurs = []
    emails_used = set()
    orcids_used = set()
    
    for cid in range(1, count + 1):
        prenom = fake.first_name()
        nom = fake.last_name()
        
        # Générer un email unique
        attempts = 0
        while attempts < 100:
            if attempts == 0:
                email = (prenom + "." + nom + "@" + fake.domain_name()).lower()
            else:
                email = (prenom + "." + nom + str(attempts) + "@" + fake.domain_name()).lower()
            if email not in emails_used:
                emails_used.add(email)
                break
            attempts += 1
        else:
            # Fallback: email avec ID unique
            email = f"chercheur{cid}@" + fake.domain_name()
            emails_used.add(email)
        
        # Générer un ORCID unique ou NULL
        orcid = None
        if random.random() < 0.5:
            attempts = 0
            while attempts < 100:
                orcid_candidate = gen_orcid(fake)
                if orcid_candidate not in orcids_used:
                    orcids_used.add(orcid_candidate)
                    orcid = orcid_candidate
                    break
                attempts += 1
        
        discipline = random.choice(["Physique", "Biologie", "Informatique", "Chimie", "Mathématiques"])
        id_labo = random.choice(laboratoires)
        chercheurs.append(cid)
        f.write(f"INSERT INTO univ_recherche.chercheur (id, prenom, nom, email, orcid, discipline, id_laboratoire) VALUES ({cid}, {_quote_sql(prenom)}, {_quote_sql(nom)}, {_quote_sql(email)}, {_quote_sql(orcid)}, {_quote_sql(discipline)}, {id_labo});\n")
    
    f.write("SELECT setval(pg_get_serial_sequence('univ_recherche.chercheur','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.chercheur),0));\n")
    return chercheurs

def generate_projets(f, fake: Faker, laboratoires: List[int], chercheurs: List[int], count: int) -> List[int]:
    """Génère les projets et retourne la liste des IDs."""
    projets = []
    
    for pid in range(1, count + 1):
        titre = fake.catch_phrase()
        description = fake.paragraph(nb_sentences=3)
        discipline = random.choice(["Physique", "Biologie", "Informatique", "Chimie", "Mathématiques"])
        budget = round(random.uniform(10000, 500000), 2)
        d_debut = fake.date_between(start_date='-5y', end_date='today')
        d_fin = None if random.random() < 0.2 else fake.date_between(start_date=d_debut, end_date='+3y')
        id_labo = random.choice(laboratoires)
        id_resp = random.choice(chercheurs) if chercheurs else None
        projets.append(pid)
        f.write(f"INSERT INTO univ_recherche.projet (id, titre, description, discipline, budget_annuel_eur, date_debut, date_fin, id_laboratoire_pilote, id_chercheur_responsable) VALUES ({pid}, {_quote_sql(titre)}, {_quote_sql(description)}, {_quote_sql(discipline)}, {budget}, {_quote_sql(d_debut)}, {_quote_sql(d_fin)}, {id_labo}, {_quote_sql(id_resp)});\n")
    
    f.write("SELECT setval(pg_get_serial_sequence('univ_recherche.projet','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.projet),0));\n")
    return projets

def generate_contrats(f, fake: Faker, projets: List[int], count: int) -> tuple[List[int], List[int]]:
    """Génère les contrats et retourne (liste des IDs, liste des IDs validés)."""
    types_contrat = ["ANR", "H2020", "Region", "Europe", "Autre"]
    contrats = []
    contrats_valides = []
    
    for coid in range(1, count + 1):
        t = random.choice(types_contrat)
        financeur = fake.company()
        intitule = fake.sentence(nb_words=6)
        montant = round(random.uniform(10000, 2000000), 2)
        duree = random.choice([12, 24, 36, None])
        d_deb = fake.date_between(start_date='-4y', end_date='today')
        d_fin = fake.date_between(start_date=d_deb, end_date='+5y')
        id_projet = random.choice(projets)
        statut = random.choices(["brouillon", "soumis", "valide"], weights=[0.5, 0.3, 0.2])[0]
        date_val = fake.date_between(start_date=d_deb, end_date='today') if statut == 'valide' else None
        url_dmp = fake.url() if statut == 'valide' else None
        contrats.append(coid)
        if statut == 'valide':
            contrats_valides.append(coid)
        f.write(f"INSERT INTO univ_recherche.contrat (id, type_contrat, financeur, intitule, montant_eur, duree_mois, date_debut, date_fin, id_projet, statut_dmp, date_validation_dmp, url_document_dmp) VALUES ({coid}, {_quote_sql(t)}, {_quote_sql(financeur)}, {_quote_sql(intitule)}, {montant}, {_quote_sql(duree)}, {_quote_sql(d_deb)}, {_quote_sql(d_fin)}, {id_projet}, {_quote_sql(statut)}, {_quote_sql(date_val)}, {_quote_sql(url_dmp)});\n")
    
    f.write("SELECT setval(pg_get_serial_sequence('univ_recherche.contrat','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.contrat),0));\n")
    return contrats, contrats_valides

def generate_jeux_donnees(f, fake: Faker, contrats: List[int], contrats_valides: List[int], chercheurs: List[int], count: int) -> List[int]:
    """Génère les jeux de données et retourne la liste des IDs."""
    jeux = []
    
    for jid in range(1, count + 1):
        # Choisir un contrat (validé si on veut une date_depot)
        if contrats_valides and random.random() < 0.4:
            id_contrat = random.choice(contrats_valides)
            date_creation = fake.date_between(start_date='-3y', end_date='today')
            date_depot = fake.date_between(start_date=date_creation, end_date='today')
        else:
            id_contrat = random.choice(contrats)
            date_creation = fake.date_between(start_date='-3y', end_date='today')
            date_depot = None
        description = fake.sentence(nb_words=12)
        id_auteur = random.choice(chercheurs)
        conditions = random.choice(["ouvert", "restreint", "sur_demande"])
        licence = random.choice(["CC-BY", "CC0", "ODbL", None])
        url = fake.url() if random.random() < 0.5 else None
        jeux.append(jid)
        f.write(f"INSERT INTO univ_recherche.jeu_donnees (id, id_contrat, description, id_auteur, conditions_acces, licence, date_creation, date_depot, url_externe) VALUES ({jid}, {id_contrat}, {_quote_sql(description)}, {id_auteur}, {_quote_sql(conditions)}, {_quote_sql(licence)}, {_quote_sql(date_creation)}, {_quote_sql(date_depot)}, {_quote_sql(url)});\n")
    
    f.write("SELECT setval(pg_get_serial_sequence('univ_recherche.jeu_donnees','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.jeu_donnees),0));\n")
    return jeux

def generate_publications(f, fake: Faker, chercheurs: List[int], count: int) -> List[int]:
    """Génère les publications avec leurs auteurs et retourne la liste des IDs."""
    publications = []
    dois_used = set()
    
    for pid in range(1, count + 1):
        titre = fake.sentence(nb_words=6)
        
        # Générer un DOI unique ou NULL
        doi = None
        if random.random() >= 0.6:
            attempts = 0
            while attempts < 100:
                doi_candidate = f"10.{random.randint(1000,9999)}/{fake.lexify(text='??????')}"
                if doi_candidate not in dois_used:
                    dois_used.add(doi_candidate)
                    doi = doi_candidate
                    break
                attempts += 1
        
        date_pub = fake.date_between(start_date='-5y', end_date='today')
        nb_pages = random.randint(1, 20) if random.random() < 0.8 else None
        url = fake.url() if random.random() < 0.5 else None
        publications.append(pid)
        f.write(f"INSERT INTO univ_recherche.publication (id, titre, doi, date_publication, nb_pages, url_externe) VALUES ({pid}, {_quote_sql(titre)}, {_quote_sql(doi)}, {_quote_sql(date_pub)}, {_quote_sql(nb_pages)}, {_quote_sql(url)});\n")
        
        # Auteurs (ordre_auteur unique par publication)
        n_auth = random.randint(1, min(5, max(1, len(chercheurs))))
        auteurs = random.sample(chercheurs, n_auth)
        for i, aid in enumerate(auteurs, start=1):
            f.write(f"INSERT INTO univ_recherche.publication_auteur (id_publication, id_chercheur, ordre_auteur) VALUES ({pid}, {aid}, {i});\n")
    
    f.write("SELECT setval(pg_get_serial_sequence('univ_recherche.publication','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.publication),0));\n")
    return publications

def generate_projet_chercheur(f, fake: Faker, projets: List[int], chercheurs: List[int]) -> None:
    """Génère les associations projet-chercheur."""
    pcid = 1
    for projet_id in projets:
        n = random.randint(1, min(6, len(chercheurs)))
        membres = random.sample(chercheurs, n)
        for m in membres:
            role = random.choice(["Investigateur", "Doctorant", "PostDoc", "Technicien"])
            d_deb = fake.date_between(start_date='-5y', end_date='today')
            d_fin = fake.date_between(start_date=d_deb, end_date='+3y') if random.random() < 0.5 else None
            charge = round(random.uniform(10, 100), 2)
            is_principal = random.random() < 0.1
            f.write(f"INSERT INTO univ_recherche.projet_chercheur (id, id_projet, id_chercheur, role, date_debut, date_fin, charge_pct, is_principal) VALUES ({pcid}, {projet_id}, {m}, {_quote_sql(role)}, {_quote_sql(d_deb)}, {_quote_sql(d_fin)}, {charge}, {'true' if is_principal else 'false'});\n")
            pcid += 1
    
    f.write("SELECT setval(pg_get_serial_sequence('univ_recherche.projet_chercheur','id'), COALESCE((SELECT MAX(id) FROM univ_recherche.projet_chercheur),0));\n")

def main(rows: int) -> None:
    fake = Faker(locale="fr_FR")
    schema_file = Path(__file__).parent.parent / "infos" / "schema_univ_recherche.sql"
    
    with INSERTS_PG.open("w", encoding="utf-8") as f:
        write_header(f, schema_file)
        
        institutions = generate_institutions(f, fake, max(3, rows // 10))
        laboratoires = generate_laboratoires(f, fake, institutions, max(5, rows // 8))
        chercheurs = generate_chercheurs(f, fake, laboratoires, max(20, rows))
        projets = generate_projets(f, fake, laboratoires, chercheurs, max(10, rows // 5))
        contrats, contrats_valides = generate_contrats(f, fake, projets, max(10, rows // 4))
        jeux_donnees = generate_jeux_donnees(f, fake, contrats, contrats_valides, chercheurs, max(5, rows // 6))
        publications = generate_publications(f, fake, chercheurs, max(10, rows // 5))
        generate_projet_chercheur(f, fake, projets, chercheurs)
        
        f.write("COMMIT;\n")

    print(f"inserts_postgres.sql créé: {INSERTS_PG}")

if __name__ == "__main__":
    nb_rows = 50000
    main(nb_rows)
