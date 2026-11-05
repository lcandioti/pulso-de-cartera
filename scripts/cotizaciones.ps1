# Baja cierres diarios y genera cotizaciones.json (formato largo) para el tablero.
# Excluye la fecha de hoy: el tablero muestra solo ruedas terminadas.
# Merval, AL30D y GD30D no tienen API gratuita con historia: se cargan desde -Manual
# (filas {id,fecha,valor} tomadas de un cierre publicado) y se acumulan desde -Salida.
param(
  [Parameter(Mandatory)][string]$Salida,
  [string]$Manual,
  [string]$Hoy = (Get-Date).ToString('yyyy-MM-dd')
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$h = @{ 'User-Agent' = 'Mozilla/5.0' }

$catalogo = @'
[
{"id":"EWZ","activo":"EWZ","nombre":"iShares MSCI Brasil","grupo":"Cartera","orden":1,"unidad":"USD","dec":2,"tipo":"pct","yahoo":"EWZ"},
{"id":"PAGS","activo":"PAGS","nombre":"PagBank","grupo":"Cartera","orden":2,"unidad":"USD","dec":2,"tipo":"pct","yahoo":"PAGS"},
{"id":"NU","activo":"NU","nombre":"Nu Holdings","grupo":"Cartera","orden":3,"unidad":"USD","dec":2,"tipo":"pct","yahoo":"NU"},
{"id":"MERVAL","activo":"Merval","nombre":"Índice en pesos","grupo":"Cartera","orden":4,"unidad":"pts","dec":0,"tipo":"pct","fuente":"Rava, vía cierre publicado"},
{"id":"CCL","activo":"Dólar CCL","nombre":"Contado con liquidación","grupo":"Cartera","orden":5,"unidad":"ARS","dec":2,"tipo":"pct","ad":"contadoconliqui"},
{"id":"RP","activo":"Riesgo país","nombre":"EMBI, J.P. Morgan","grupo":"Cartera","orden":6,"unidad":"pb","dec":0,"tipo":"abs","rp":true},
{"id":"MAY","activo":"Dólar mayorista","nombre":"Com. A 3500, BCRA","grupo":"Argentina","orden":19,"unidad":"ARS","dec":2,"tipo":"pct","bcra":5},
{"id":"BVSP","activo":"Ibovespa","nombre":"Bolsa de Brasil","grupo":"Brasil","orden":10,"unidad":"pts","dec":0,"tipo":"pct","yahoo":"^BVSP"},
{"id":"BRL","activo":"USD/BRL","nombre":"PTAX venta, BCB","grupo":"Brasil","orden":11,"unidad":"BRL","dec":4,"tipo":"pct","ptax":true},
{"id":"GGAL","activo":"GGAL","nombre":"ADR Grupo Galicia","grupo":"Argentina","orden":20,"unidad":"USD","dec":2,"tipo":"pct","yahoo":"GGAL"},
{"id":"YPF","activo":"YPF","nombre":"ADR YPF","grupo":"Argentina","orden":21,"unidad":"USD","dec":2,"tipo":"pct","yahoo":"YPF"},
{"id":"ARGT","activo":"ARGT","nombre":"ETF MSCI Argentina","grupo":"Argentina","orden":22,"unidad":"USD","dec":2,"tipo":"pct","yahoo":"ARGT"},
{"id":"AL30D","activo":"AL30D","nombre":"Bonar 2030 en dólares","grupo":"Argentina","orden":23,"unidad":"USD","dec":2,"tipo":"pct","fuente":"Rava, vía cierre publicado"},
{"id":"BLUE","activo":"Dólar blue","nombre":"Mercado informal","grupo":"Argentina","orden":24,"unidad":"ARS","dec":2,"tipo":"pct","ad":"blue"},
{"id":"SPX","activo":"S&P 500","nombre":"Bolsa de EE. UU.","grupo":"Global","orden":30,"unidad":"pts","dec":0,"tipo":"pct","yahoo":"^GSPC"},
{"id":"VIX","activo":"VIX","nombre":"Volatilidad implícita","grupo":"Global","orden":31,"unidad":"pts","dec":2,"tipo":"abs","yahoo":"^VIX"},
{"id":"UST10","activo":"Treasury 10 años","nombre":"Rendimiento","grupo":"Global","orden":32,"unidad":"%","dec":2,"tipo":"abs","yahoo":"^TNX"},
{"id":"BRENT","activo":"Brent","nombre":"Petróleo, futuro","grupo":"Global","orden":33,"unidad":"USD","dec":2,"tipo":"pct","yahoo":"BZ=F"},
{"id":"SOJA","activo":"Soja","nombre":"Futuro CBOT","grupo":"Global","orden":34,"unidad":"¢/bu","dec":0,"tipo":"pct","yahoo":"ZS=F"}
]
'@ | ConvertFrom-Json

$desde = ([datetime]$Hoy).AddDays(-95).ToString('yyyy-MM-dd')
$puntos = @{}   # id -> hashtable fecha->valor
$fuentes = @{}
$fallas = New-Object System.Collections.ArrayList
function Sumar($id, $fecha, $valor) {
  if ($null -eq $valor -or $fecha -ge $Hoy -or $fecha -lt $desde) { return }
  if (-not $puntos.ContainsKey($id)) { $puntos[$id] = @{} }
  $puntos[$id][$fecha] = [double]$valor
}

foreach ($c in $catalogo) {
  try {
    if ($c.yahoo) {
      $s = [uri]::EscapeDataString($c.yahoo)
      $m = (Invoke-RestMethod -Headers $h -TimeoutSec 30 "https://query1.finance.yahoo.com/v8/finance/chart/$s`?range=3mo&interval=1d").chart.result[0]
      $off = [int]$m.meta.gmtoffset; $cl = $m.indicators.quote[0].close
      for ($i = 0; $i -lt $m.timestamp.Count; $i++) {
        Sumar $c.id ([DateTimeOffset]::FromUnixTimeSeconds([long]$m.timestamp[$i] + $off).UtcDateTime.ToString('yyyy-MM-dd')) $cl[$i]
      }
      $fuentes[$c.id] = 'Yahoo Finance'
    } elseif ($c.ad) {
      foreach ($d in (Invoke-RestMethod -TimeoutSec 30 "https://api.argentinadatos.com/v1/cotizaciones/dolares/$($c.ad)")) { Sumar $c.id $d.fecha $d.venta }
      $fuentes[$c.id] = 'ArgentinaDatos'
    } elseif ($c.rp) {
      foreach ($d in (Invoke-RestMethod -TimeoutSec 30 'https://api.argentinadatos.com/v1/finanzas/indices/riesgo-pais')) { Sumar $c.id $d.fecha $d.valor }
      $fuentes[$c.id] = 'ArgentinaDatos'
    } elseif ($c.ptax) {
      $i = ([datetime]$desde).ToString('MM-dd-yyyy'); $f = ([datetime]$Hoy).ToString('MM-dd-yyyy')
      $u = "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/CotacaoDolarPeriodo(dataInicial=@i,dataFinalCotacao=@f)?@i='$i'&@f='$f'&`$format=json&`$select=cotacaoVenda,dataHoraCotacao"
      foreach ($d in (Invoke-RestMethod -TimeoutSec 30 $u).value) { Sumar $c.id $d.dataHoraCotacao.Substring(0, 10) $d.cotacaoVenda }
      $fuentes[$c.id] = 'Banco Central do Brasil'
    } elseif ($c.bcra) {
      $r = Invoke-RestMethod -TimeoutSec 30 "https://api.bcra.gob.ar/estadisticas/v4.0/monetarias/$($c.bcra)?limit=70"
      foreach ($d in $r.results[0].detalle) { Sumar $c.id $d.fecha $d.valor }
      $fuentes[$c.id] = 'BCRA'
    } else { $fuentes[$c.id] = $c.fuente }
  } catch { [void]$fallas.Add("$($c.id): $($_.Exception.Message)") }
}

# Acumulado previo: conserva lo ya publicado para las series manuales o las que hoy fallaron.
if (Test-Path $Salida) {
  foreach ($r in (Get-Content $Salida -Raw -Encoding UTF8 | ConvertFrom-Json).rows) {
    if (-not $puntos.ContainsKey($r.id) -or -not $puntos[$r.id].ContainsKey($r.fecha)) {
      if (($catalogo | Where-Object id -eq $r.id).fuente -or ($fallas -match "^$($r.id):")) { Sumar $r.id $r.fecha $r.valor; if (-not $fuentes[$r.id]) { $fuentes[$r.id] = $r.fuente } }
    }
  }
}
if ($Manual -and (Test-Path $Manual)) {
  foreach ($r in (Get-Content $Manual -Raw -Encoding UTF8 | ConvertFrom-Json)) { Sumar $r.id $r.fecha $r.valor }
}

$rows = foreach ($c in $catalogo) {
  if (-not $puntos.ContainsKey($c.id)) { continue }
  foreach ($k in ($puntos[$c.id].Keys | Sort-Object)) {
    [pscustomobject]@{ id = $c.id; activo = $c.activo; nombre = $c.nombre; grupo = $c.grupo; orden = $c.orden; unidad = $c.unidad; dec = $c.dec; tipo = $c.tipo; fecha = $k; valor = [math]::Round($puntos[$c.id][$k], [math]::Max($c.dec, 2) + 2); fuente = $fuentes[$c.id] }
  }
}
$json = @{ rows = @($rows) } | ConvertTo-Json -Depth 4 -Compress
[IO.File]::WriteAllText($Salida, $json, (New-Object Text.UTF8Encoding $false))

# Resumen para quien corre el script
foreach ($c in $catalogo) {
  $p = $rows | Where-Object id -eq $c.id
  if (-not $p) { "{0,-7} SIN DATOS" -f $c.id; continue }
  $u = @($p)[-1]; $a = if (@($p).Count -gt 1) { @($p)[-2] } else { $null }
  "{0,-7} {1} {2}  previo {3} {4}" -f $c.id, $u.fecha, $u.valor, $a.fecha, $a.valor
}
if ($fallas.Count) { 'FALLAS:'; $fallas }
