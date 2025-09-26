# CPI kwartaalmutaties – Koffie & Boeken (CBS StatLine 83131NED)

Dit project haalt CPI-data (Consumentenprijsindex, 2015=100) uit de CBS StatLine API.  
Met deze cijfers worden kwartaalindices en kwartaalmutaties berekend voor twee producten die mij na aan het hart gaan:

- Koffie (`CPI012110`)  
- Boeken (`CPI095100`)  

Alle resultaten worden opgeslagen in een SQLite database (`output/cpi.sqlite`).  
De plots worden niet als losse bestanden opgeslagen, maar als PNG-blobs in dezelfde database. 
Het runnen van het script haalt weer de blobs uit de SQLite op om de plots in Rstudio te laten zien.

# Data ophalen
- Data komt uit tabel `83131NED` (*Consumentenprijzen; prijsindex 2015=100*).  
- Via `cbsodataR` wordt de API aangeroepen.  
- De maanddata wordt gefilterd op de gekozen producten.  

# Van maand naar kwartaal
- Maandcijfers worden omgezet naar kwartalen door het gemiddelde van 3 maanden te nemen.  
- Alleen complete kwartalen (3 maanden) worden gebruikt.  
- Daarna wordt de kwartaalmutatie (`qoq_pct`) berekend t.o.v. het vorige kwartaal.  

# Keuze van het juiste kwartaal
- Het script kijkt naar de huidige datum (`Sys.Date()`).  
- Op basis daarvan wordt het laatste afgeronde kwartaal gekozen als **target**.  
- Voorbeeld: op 24 september 2025 → huidig kwartaal = Q3 → target = Q2.  
- Als dat kwartaal nog niet beschikbaar is in de data, wordt het laatst bekende complete kwartaal gebruikt.  

# Opslag in SQLite
Er worden drie tabellen gemaakt:
- `cpi_monthly` → maanddata met indexwaarden  
- `cpi_quarterly` → kwartaaldata met index en mutaties  
- `plots` → de twee grafieken, opgeslagen als PNG-blobs  

# Visualisaties
Twee grafieken worden aangemaakt:
1. CPI van de laatste 12 maanden  
2. De laatste 4 kwartaalmutaties (QoQ)  

Deze worden:
- direct getoond in RStudio  
- ook als PNG-blobs opgeslagen in de database  

# Gebruik

1. Clone deze repo of download het script.  
2. Open het script in RStudio en run via Source.   

Het script:
- Installeert automatisch de benodigde packages (`cbsodataR`, `dplyr`, `ggplot2`, `DBI`, `RSQLite`, `png`, `grid`)  
- Haalt data op en verwerkt dit  
- Schrijft alles naar `output/cpi.sqlite`  
- Laat de grafieken en de laatste kwartaalmutatie in de console zien.
