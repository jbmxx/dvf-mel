"""
Lille property market — median price per m² by commune, 2021–2025.
Source: raw DGFiP DVF files, cleaned with DuckDB (see sql/ and docs/filter_log.md).
"""

import pandas as pd
import plotly.express as px
import streamlit as st

st.set_page_config(page_title="Lille property prices", layout="wide")


@st.cache_data
def load_data():
    df = pd.read_csv("data/ref/prix_m2_median.csv")
    return df


df = load_data()

st.title("Lille metropolitan area — median price per m²")
st.caption(
    "74,937 transactions, 95 communes, 2021–2025. "
    "Built from raw DGFiP land registry files (20.4M rows) with DuckDB."
)

# --- Sidebar controls ---
st.sidebar.header("Filters")

type_bien = st.sidebar.radio("Property type", ["Appartement", "Maison"])

annee = st.sidebar.selectbox(
    "Year", sorted(df["annee"].unique(), reverse=True)
)

fiable_only = st.sidebar.checkbox(
    "Reliable cells only (≥10 sales)", value=True
)

# --- Filtering ---
d = df[(df["type_bien"] == type_bien) & (df["annee"] == annee)]
if fiable_only:
    d = d[d["fiable"]]

# --- Headline metrics ---
c1, c2, c3 = st.columns(3)
c1.metric("Communes shown", len(d))
c2.metric("Transactions", f"{int(d['n_ventes'].sum()):,}")
c3.metric(
    "Median across communes",
    f"{int(d['prix_m2_median'].median()):,}",
    help="Median of commune-level medians, unweighted — each commune counts once, "
         "regardless of transaction volume.",
)

# --- Ranking chart ---
st.subheader(f"{type_bien} — {annee}")

ranked = d.sort_values("prix_m2_median", ascending=True)

fig = px.bar(
    ranked,
    x="prix_m2_median",
    y="nom_commune",
    orientation="h",
    labels={"prix_m2_median": "Median €/m²", "nom_commune": ""},
    height=max(400, 18 * len(ranked)),
    hover_data={"n_ventes": True},
)
fig.update_layout(margin=dict(l=0, r=0, t=10, b=0))
st.plotly_chart(fig, width="stretch")

# --- Time series ---
st.subheader("Price trend by commune")

communes = st.multiselect(
    "Select communes",
    sorted(df["nom_commune"].unique()),
    default=["Lille", "Roubaix", "Tourcoing", "Marcq-en-Barœul"],
)

if communes:
    ts = df[(df["nom_commune"].isin(communes)) & (df["type_bien"] == type_bien)]
    if fiable_only:
        ts = ts[ts["fiable"]]
    fig2 = px.line(
        ts.sort_values("annee"),
        x="annee",
        y="prix_m2_median",
        color="nom_commune",
        markers=True,
        labels={"prix_m2_median": "Median €/m²", "annee": "", "nom_commune": ""},
    )
    fig2.update_xaxes(dtick=1)
    st.plotly_chart(fig2, width="stretch")

# --- Data table ---
with st.expander("View underlying data"):
    st.dataframe(d, width="stretch", hide_index=True)