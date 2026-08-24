-- Row-level DVF → mutation-level table, MEL perimeter.
-- One sale spans several parcel/lot rows with the price repeated, so rows are
-- collapsed on a composite key. No quality filter applied here: counters are
-- carried so each filter can be quantified downstream without rescanning 2.6 GB.

CREATE OR REPLACE TABLE mutations_mel AS
WITH src AS (
    SELECT
        concat_ws('|', "Date mutation", "No disposition", "Valeur fonciere",
                       "Code departement", lpad("Code commune", 3, '0')) AS id_mutation,
        "Code departement" || lpad("Code commune", 3, '0') AS code_insee,
        try_strptime("Date mutation", '%d/%m/%Y') AS date_mutation,
        "Nature mutation" AS nature,
        try_cast(replace("Valeur fonciere", ',', '.') AS DOUBLE) AS valeur,
        "Code type local" AS type_local,
        try_cast("Surface reelle bati" AS INTEGER) AS surface,
        try_cast("Nombre pieces principales" AS INTEGER) AS pieces
    FROM read_csv('data/raw/ValeursFoncieres-*.txt',
                  delim = '|', header = true, all_varchar = true)
    WHERE "Code departement" = '59'
),
mel AS (
    SELECT s.* FROM src s
    JOIN communes_mel m ON s.code_insee = m.code_insee
),
agg AS (
    SELECT
        id_mutation,
        any_value(code_insee)    AS code_insee,
        any_value(date_mutation) AS date_mutation,
        any_value(nature)        AS nature,
        any_value(valeur)        AS valeur,
        count(*)                                           AS n_lignes,
        count(*) FILTER (WHERE type_local IN ('1','2'))     AS n_bati,
        count(*) FILTER (WHERE type_local = '3')            AS n_dependances,
        count(*) FILTER (WHERE type_local = '4')            AS n_commercial,
        any_value(type_local) FILTER (WHERE type_local IN ('1','2')) AS type_bien,
        sum(surface) FILTER (WHERE type_local IN ('1','2')) AS surface_bati,
        sum(pieces)  FILTER (WHERE type_local IN ('1','2')) AS nb_pieces
    FROM mel
    GROUP BY id_mutation
)
SELECT *, year(date_mutation) AS annee, round(valeur / surface_bati, 0) AS prix_m2
FROM agg;