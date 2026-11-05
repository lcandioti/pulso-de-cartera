# Pulso de Cartera

Resumen diario de noticias financieras de Brasil (EWZ, PAGS, NU) y Argentina (Merval, tipo de cambio, bonos y riesgo país), con una lectura de cada noticia y su fuente.

## Cómo funciona

- `index.html` es la página, sin dependencias.
- `data/datos.js` contiene las cotizaciones y los informes. Los mismos datos están en `data/cotizaciones.json` y `data/informes.json`.
- `scripts/cotizaciones.ps1` baja los cierres de Yahoo Finance, ArgentinaDatos, BCRA y Banco Central do Brasil. Merval y AL30D salen de cierres publicados.
- Claude redacta el informe cada mañana con una tarea programada en la PC del autor y lo sube a este repositorio.

Las lecturas son interpretaciones generadas automáticamente y pueden contener errores. No constituyen asesoramiento financiero ni recomendaciones de inversión.
