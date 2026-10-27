# Prumo: busca as matérias de arquitetura das fontes, traduz o que vem de fora, marca os temas e grava data/feed.json.
# Roda no GitHub Actions (pwsh 7, Linux) a cada 2 horas e também no Windows PowerShell 5.1 para testar.
#
# Campos de cada matéria no feed.json (nomes curtos para o arquivo ficar leve no celular):
#   id   identificador     s   fonte (id em sources.json)   u   link
#   t    título original   d   resumo original              l   idioma (pt, en, es, fr, it)
#   tt   título traduzido  td  resumo traduzido             img imagem
#   at   data de publicação (ISO)   fs  primeira vez que o coletor viu
#   au   autor   tg  temas   m  minutos de leitura (quando o feed traz o texto inteiro)   ix  já procurou imagem na página
[CmdletBinding()]
param(
  [string]$Out,
  [string]$Sources,
  [switch]$NoTranslate,
  [switch]$NoImages
)

$ErrorActionPreference = 'Stop'
# o Windows PowerShell 5.1 não conhece $PSScriptRoot nos valores padrão do param
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Out) { $Out = [IO.Path]::GetFullPath((Join-Path $here '../data/feed.json')) }
if (-not $Sources) { $Sources = Join-Path $here 'sources.json' }
if ($PSVersionTable.PSVersion.Major -lt 6) {
  Add-Type -AssemblyName System.Net.Http
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  [Net.ServicePointManager]::DefaultConnectionLimit = 8
}

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'
function New-Http([int]$Seconds) {
  $h = New-Object System.Net.Http.HttpClientHandler
  $h.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
  $h.AllowAutoRedirect = $true
  $c = New-Object System.Net.Http.HttpClient($h)
  $c.Timeout = [TimeSpan]::FromSeconds($Seconds)
  [void]$c.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', $UA)
  [void]$c.DefaultRequestHeaders.TryAddWithoutValidation('Accept', 'application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.9, text/html;q=0.8, */*;q=0.5')
  [void]$c.DefaultRequestHeaders.TryAddWithoutValidation('Accept-Language', 'pt-BR,pt;q=0.9,en;q=0.8')
  $c
}
$script:Http = New-Http 25
$script:PageHttp = New-Http 12

# ---------- temas ----------
# A ordem define o tema principal de cada matéria: os mais específicos vêm antes, "projeto" (obra em geral) por último.
# "academia" vem só das revistas acadêmicas.
$TagRules = @(
  @{ id = 'concursos'; label = 'Concursos & Prêmios'; re = '\bconcursos?\b|competi[çc][ãa]o de (arquitetura|projeto|ideias)|\bcompetitions?\b|\bconcorso|\bconcours\b|\bpr[êe]mios?\b|premia[çc]|\bprizes?\b|\bawards?\b|\bpremio\b|\bprix\b|pritzker|\bvencedor|\bwinners?\b|\bwins\b|shortlist|finalist|open call|chamada (aberta|p[úu]blica)|^results:|resultado do concurso' },
  @{ id = 'patrimonio'; label = 'Patrimônio'; re = 'patrim[ôo]ni|patrimoine|\bheritage|\btombad|tombamento|\biphan\b|\bunesco|restaur(o|a[çc][ãa]o|aci[óo]n|ation|ar\b|ad[oa]s?\b|ed\b|ing\b)|\brestor(e|ed|ing)\b|preserva[çc]|preservation|conserva[çc][ãa]o do|conservation of|\bretrofit|adaptive reuse|reuso adaptativo|requalifica[çc][ãa]o de|reabilita[çc]|rehabilitat|riqualifica|\bru[íi]nas?\b|\bruins?\b|listed building|centro hist[óo]rico|historic (building|centre|center|district)' },
  @{ id = 'habitacao'; label = 'Habitação'; re = 'habita[çc][ãa]o|habitacional|\bmoradias?\b|\bhousing\b|affordable|\bmcmv\b|minha casa,? minha vida|d[ée]ficit habitacional|\baluguel|\brent(al|s)?\b|cohousing|co-housing|\bvivienda|\balloggi|\blogement|sem-teto|homeless|situa[çc][ãa]o de rua|conjunto habitacional|\bhabitar\b|\bdespejo|eviction' },
  @{ id = 'social'; label = 'Cidade & Sociedade'; re = 'direito [àa] cidade|right to the city|desigualdad|inequal|segrega[çc]|segregat|\bfavelas?\b|periferi|\binclus(ão|ivo|iva|ion|ive)\b|acessibilidade|accessib|\bacess[íi]ve(l|is)\b|desenho universal|universal design|\bg[êe]nero\b|\bgender\b|feminis|racis|antirrac|quilomb|ind[íi]genas?\b|indigenous|justi[çc]a (social|espacial|clim[áa]tica)|social justice|spatial justice|vulnerab|\bpobreza|poverty|assentamentos? informa|informal settlement|\bocupa[çc](ão|ões)\b|\bmtst\b|movimentos? socia|participa[çc][ãa]o (social|popular|cidad)|participatory|community-led|assist[êe]ncia t[ée]cnica|\bathis\b|refugiad|refugee|\bmigra' },
  @{ id = 'mobilidade'; label = 'Mobilidade'; re = 'mobilidade|\bmobility|movilidad|transporte|\btransport|\bmetr[ôo]\b|\bsubway|\btransit\b|[ôo]nibus|\bbus(es)?\b|\bbrt\b|ciclovia|bicicleta|\bbik(e|es|ing)\b|cycl(ing|ists?)|bike lanes?|pedestr|pedonal|caminhab|walkab|cal[çc]adas?\b|sidewalk|\btram\b|\bvlt\b|tr[áa]fego|\btraffic|car-free|estacionamento|\bparking|\bmotos?\b' },
  @{ id = 'paisagismo'; label = 'Paisagismo'; re = 'paisag|landscape|paesaggi|paysag|\bjardi(m|ns|n|nes)\b|\bgardens?\b|giardin|\bparques?\b|\bparks?\b|\bparco\b|burle marx|vegeta[çc]|vegetation|arboriza|\btrees?\b|\b[áa]rvores?\b|floresta urbana|urban forest|infraestrutura verde|green infrastructure|espa[çc]os? livres?|public realm|baseadas? na natureza|nature-based|jardim de chuva|rain garden' },
  @{ id = 'interiores'; label = 'Interiores'; re = '\binteriores\b|\binteriors?\b|interior design|\binterni\b|int[ée]rieur|decora[çc]|\bd[ée]cor\b|mobili[áa]rio|furniture|\bm[óo]veis\b|\bcadeiras?\b|\bchairs?\b|marcenaria|joinery|ilumina[çc][ãa]o|\blighting|lumin[áa]ria|\blamps?\b|\bsof[áa]s?\b|\bapartamentos?\b|\bapartments?\b|\bloft\b|\bcozinhas?\b|\bkitchens?\b|banheiro|bathroom|sala de estar|living room|showroom|\blojas?\b|\bstores?\b|\bshop\b|\bretail|restaurante|restaurant|\bbar\b|\bhot[ée]is\b|\bhotels?\b|\bcaf[ée]\b' },
  @{ id = 'sustentabilidade'; label = 'Sustentabilidade'; re = 'sustent[áa]ve|sustentabil|sustainab|sostenib|\bclima\b|\bclim[áa]tic|climat|carbono|carbon|net[- ]zero|emiss(ões|ions)|\benergia|\benergy|\bsolar\b|fotovolt|photovolt|passiv(e ?house|haus)|bioclim|ventila[çc][ãa]o natural|natural ventilation|resili[êe]n|enchente|inunda[çc]|\bflood|ondas? de calor|heat ?waves?|ilha de calor|urban heat|telhados? verdes?|green roof|biof[íi]li|economia circular|circular economy|baixo carbono|low-carbon|\bcop ?30\b|\besg\b' },
  @{ id = 'materiais'; label = 'Materiais & Técnica'; re = '\bmateriai?s\b|\bmaterials?\b|\bmateriales\b|\bmateriali\b|\bmadeira|\bwood(en)?\b|timber|\bclt\b|\blegno\b|\bbois\b|concreto|concrete|cemento|b[ée]ton|\ba[çc]o\b|\bsteel\b|tijolo|\bbricks?\b|ladrillo|mattoni|\bbambu|bamboo|\btaipa|rammed earth|\badobe\b|terra crua|earthen|\bpedras?\b|\bstone\b|\bvidro\b|\bglass\b|cer[âa]mic|ceramic|terracot|porcelanato|revestimento|cladding|estrutural|structural|engenharia|engineer|constru[çc][ãa]o civil|canteiro de obras|construction site|pr[ée]-?fabric|prefab|\bmodular|impress[ãa]o 3d|3d[- ]print|argamassa|mortar|telhado|\broof(ing)?\b' },
  @{ id = 'tecnologia'; label = 'BIM & Tecnologia'; re = '\bbim\b|\brevit\b|archicad|\brhino\b|grasshopper|param[ée]tric|parametri|computacional|computational|digital twin|g[êe]meo digital|intelig[êe]ncia artificial|artificial intelligence|\bIA\b|\bAI\b|machine learning|generativ|\brob[ôo]s?\b|\brobot|fabrica[çc][ãa]o digital|digital fabrication|realidade (virtual|aumentada)|virtual reality|augmented reality|\bsoftware|algoritm|algorithm|\bdrones?\b|smart cit|cidades? inteligentes?|tecnolog|technolog' },
  @{ id = 'eventos'; label = 'Bienais & Eventos'; re = '\bbienal|biennal|biennale|biennial|trienal|triennale|exposi[çc](ão|ões)|exhibitions?\b|\bexhibit\b|\bmostra\b|\bfeiras?\b|\bfairs?\b|semin[áa]rios?|seminar|congresso|congress|conference|confer[êe]ncia|palestras?|lectures?\b|\bwebinar|\bevento|\bevents?\b|festival|simp[óo]sio|symposium|design week|semana de design|\bsalone\b|casacor|serpentine|installation' },
  @{ id = 'profissao'; label = 'Profissão'; re = '\bcau\b|cau/br|cau/sp|\biab\b|\briba\b|\baia\b|conselho de arquitetura|arquitet[oa]s? e urbanistas?|exerc[íi]cio profissional|\bcarreira|\bcareers?\b|escrit[óo]rios? de arquitetura|architecture (firm|practice|office)s?|\bpractices\b|honor[áa]rios|\bfees\b|sal[áa]rios?\b|\bsalar(y|ies)\b|\bempregos?\b|\bjobs?\b|\bhiring\b|licita[çc]|procurement|\bedital\b|\beditais\b|normas? t[ée]cnicas?|\babnt\b|\bnbr\b|ensino de arquitetura|architecture education|architecture schools?|faculdades? de arquitetura|estudantes de arquitetura|architecture students|mercado de arquitetura|incorporadora|construtora|real estate|mercado imobili|\bcontractors?\b|empreiteir' },
  @{ id = 'urbanismo'; label = 'Urbanismo'; re = '(?<!(arquitetura|arquitet[oa]s) e |architecture and )\burban|urbaniza|\bcidades?\b|\bcity\b|\bcities\b|\bciudad|\bcitt[àa]\b|\bville\b|metr[óo]pole|metropol|plano diretor|zoneamento|zoning|uso do solo|land use|espa[çc]o p[úu]blico|public space|espacio p[úu]blico|\bpra[çc]as?\b|\bplazas?\b|\bbairros?\b|neighbou?rhoods?|quarteir|masterplan|master plan|planejamento|\bplanning\b|gentrifica|regenera[çc]|regeneration|densifica|densidade|\bdensity\b|\bsuburb|downtown|\bruas?\b|\bstreets?\b|\bavenidas?\b' },
  @{ id = 'teoria'; label = 'Teoria & História'; re = '\bteoria|\btheor(y|ies|ist)|cr[íi]tica d[aeo]|criticism|historiograf|historiograph|hist[óo]ria da arquitetura|architectural history|history of architecture|modernis|brutalis|bauhaus|niemeyer|lina bo bardi|corbusier|\bmies\b|l[úu]cio costa|artigas|mendes da rocha|\breidy\b|\bkahn\b|\baalto\b|lloyd wright|\bzaha\b|koolhaas|\bsiza\b|\bensaios?\b|\bessays?\b|manifest(o|e)\b|\blivros?\b|\bbooks?\b|filosof|philosoph|fenomenolog|phenomenolog|vitr[úu]vi|p[óo]s-?modern|postmodern|tipolog|typolog|monograf|biografi|biograph|\bobituary|\bmorre\b|\bdies\b' },
  @{ id = 'brasil'; label = 'Brasil'; re = '\bbrasil|\bbrazil|brasileir|brazilian|s[ãa]o paulo|rio de janeiro|bras[íi]lia|belo horizonte|\brecife\b|fortaleza|porto alegre|curitiba|\bmanaus\b|\bbel[ée]m\b|goi[âa]nia|florian[óo]polis|jo[ãa]o pessoa|macei[óo]|aracaju|teresina|s[ãa]o lu[íi]s|campinas|niter[óo]i|ouro preto|\bolinda\b|paraty|nordeste|amaz[ôo]nia' },
  @{ id = 'projeto'; label = 'Projetos & Obras'; re = '\bcasas?\b|\bhouses?\b|\bhomes?\b|resid[êe]nci|\bresidences?\b|residential|edif[íi]cios?|\bbuildings?\b|\btorres?\b|\btowers?\b|arranha-c[ée]u|skyscraper|pavilh[ãa]o|pavilion|\bescolas?\b|\bschools?\b|\bmuseus?\b|\bmuseums?\b|biblioteca|\blibrar(y|ies)\b|\bigrejas?\b|\bchurch|\bcapela|\bchapel|centro cultural|cultural cent|\bsede\b|headquarters|\boffices?\b|\bhospita(l|is)\b|est[áa]dio|stadium|\bteatro|theat(er|re)|aeroporto|airport|\besta[çc](ão|ões)\b|\bstations?\b|\bpontes?\b|\bbridges?\b|\bobras?\b|projetad[oa]|designed by|\bdesigns\b|completes|conclu[íi]d|inaugur|\breforma\b|renovat|\bextension\b|amplia[çc][ãa]o|\bcabins?\b|\bcabanas?\b|\bvillas?\b|chal[ée]|condom[íi]nio|mixed-use|uso misto|\bcampus|\bsaunas?\b' },
  @{ id = 'academia'; label = 'Pesquisa'; re = $null }
)
$RegexOpts = [Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'
foreach ($r in $TagRules) { if ($r.re) { $r.rx = New-Object Text.RegularExpressions.Regex($r.re, $RegexOpts) } }
# Veículos gerais (filter = true) só entram com palavra forte de arquitetura ou cidade no título ou no resumo;
# assim política e economia ficam de fora, mas plano diretor, habitação e espaço público entram.
$FilterRx = New-Object Text.RegularExpressions.Regex(('arquitet|architect|architett|arquitect|urbanis|urbaniz|\burban|paisag|landscape|habita[çc][ãa]o|\bmoradia|\bhousing|patrim[ôo]ni|heritage|tombament|' +
  'plano diretor|zoneamento|zoning|espa[çc]o p[úu]blico|public space|mobilidade urbana|edif[íi]cio|\bbuildings?\b|interiores|interior design|constru[çc][ãa]o civil|pritzker|bienal de arquitetura|niemeyer|lina bo bardi|' +
  '\bmuseus?\b|\bmuseums?\b|\bpra[çc]as?\b|\bparques?\b|gentrifica|\bfavelas?\b|direito [àa] cidade|\bbairros?\b|neighbou?rhood|skyscraper|arranha-c|\bdesign\b|mobili[áa]rio|furniture'), $RegexOpts)

# O título manda: os temas que aparecem nele vêm primeiro, e só depois os do resumo e das categorias.
function Get-Tags([string]$Text, $Src, [string]$Title) {
  $found = New-Object Collections.Generic.List[string]
  $inTitle = New-Object Collections.Generic.List[string]
  foreach ($r in $TagRules) {
    if (-not $r.rx) { continue }
    if ($Title -and $r.rx.IsMatch($Title)) { $inTitle.Add($r.id); $found.Add($r.id) }
    elseif ($r.rx.IsMatch($Text)) { $found.Add($r.id) }
  }
  if ($Src.kind -eq 'academia' -and -not $found.Contains('academia')) { $found.Add('academia') }
  foreach ($t in @($Src.tags)) {
    if ($found.Count -ge 3) { break }
    if (-not $found.Contains($t)) { $found.Add($t) }
  }
  # dentro de cada grupo (título, resto) vale a ordem de prioridade dos temas
  $first = @($TagRules | Where-Object { $inTitle.Contains($_.id) } | ForEach-Object { $_.id })
  $rest = @($TagRules | Where-Object { $found.Contains($_.id) -and -not $inTitle.Contains($_.id) } | ForEach-Object { $_.id })
  @{ tags = @(@($first) + @($rest) | Select-Object -First 4) }
}

# ---------- rede ----------
function Get-Many([string[]]$Urls, $Client, [int]$Parallel = 16) {
  $out = @{}
  for ($i = 0; $i -lt $Urls.Count; $i += $Parallel) {
    $end = [Math]::Min($i + $Parallel, $Urls.Count) - 1
    $tasks = @{}
    foreach ($u in @($Urls[$i..$end])) {
      try { $tasks[$u] = $Client.GetAsync($u) } catch { $out[$u] = @{ err = $_.Exception.Message } }
    }
    foreach ($u in @($tasks.Keys)) {
      try {
        $resp = $tasks[$u].GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) { $out[$u] = @{ err = "HTTP $([int]$resp.StatusCode)" }; continue }
        $bytes = $resp.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $cs = $null
        if ($resp.Content.Headers.ContentType) { $cs = $resp.Content.Headers.ContentType.CharSet }
        $out[$u] = @{ bytes = $bytes; charset = $cs; final = $resp.RequestMessage.RequestUri.AbsoluteUri }
      } catch {
        $e = $_.Exception
        while ($e.InnerException) { $e = $e.InnerException }
        $out[$u] = @{ err = $e.Message }
      }
    }
  }
  $out
}

function ConvertTo-Text([byte[]]$Bytes, [string]$Charset) {
  $head = [Text.Encoding]::ASCII.GetString($Bytes, 0, [Math]::Min(400, $Bytes.Length))
  $name = $null
  if ($head -match '<\?xml[^>]*encoding\s*=\s*["'']([A-Za-z0-9_\-]+)') { $name = $Matches[1] }
  elseif ($Charset) { $name = $Charset.Trim('"') }
  $enc = [Text.Encoding]::UTF8
  if ($name) { try { $enc = [Text.Encoding]::GetEncoding($name) } catch { } }
  $s = $enc.GetString($Bytes)
  if ($s.Length -gt 0 -and $s[0] -eq [char]0xFEFF) { $s = $s.Substring(1) }
  $s
}

# ---------- XML ----------
# Feeds trazem entidades HTML (&nbsp;, &rsquo;) que o XML não conhece: viram números antes de ler.
$EntityRx = [regex]'&(?!(?:amp|lt|gt|quot|apos);|#\d+;|#x[0-9a-fA-F]+;)([A-Za-z][A-Za-z0-9]{1,31};)?'
$EntityFix = [Text.RegularExpressions.MatchEvaluator]{
  param($m)
  $name = $m.Groups[1].Value
  if (-not $name) { return '&amp;' }
  $dec = [Net.WebUtility]::HtmlDecode('&' + $name)
  if ($dec -eq ('&' + $name)) { return '&amp;' + $name }
  $sb = New-Object Text.StringBuilder
  for ($i = 0; $i -lt $dec.Length; $i++) {
    $cp = [int]$dec[$i]
    if ([char]::IsHighSurrogate($dec[$i]) -and $i + 1 -lt $dec.Length) { $cp = [char]::ConvertToUtf32($dec[$i], $dec[$i + 1]); $i++ }
    [void]$sb.Append('&#').Append($cp).Append(';')
  }
  $sb.ToString()
}

function Read-Feed([string]$Text) {
  $i = $Text.IndexOf('<')
  if ($i -lt 0) { throw 'resposta sem XML' }
  if ($i -gt 0) { $Text = $Text.Substring($i) }
  if ($Text -match '^<!doctype html|^<html') { throw 'veio uma página HTML em vez do feed' }
  $Text = [regex]::Replace($Text, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
  $Text = $EntityRx.Replace($Text, $EntityFix)
  $set = New-Object Xml.XmlReaderSettings
  $set.DtdProcessing = [Xml.DtdProcessing]::Ignore
  $set.XmlResolver = $null
  $doc = New-Object Xml.XmlDocument
  $doc.XmlResolver = $null
  $reader = [Xml.XmlReader]::Create((New-Object IO.StringReader $Text), $set)
  try { $doc.Load($reader) } finally { $reader.Dispose() }
  $doc
}

$NsMedia = 'http://search.yahoo.com/mrss/'
$NsAtom = 'http://www.w3.org/2005/Atom'
$XP = @{
  title    = "*[local-name()='title' and namespace-uri()!='$NsMedia']"
  link     = "*[local-name()='link' and namespace-uri()!='$NsAtom']"
  atomLink = "*[local-name()='link' and namespace-uri()='$NsAtom' and (not(@rel) or @rel='alternate')]"
  origLink = "*[local-name()='origLink']"
  guid     = "*[local-name()='guid']"
  desc     = "*[(local-name()='description' and namespace-uri()!='$NsMedia') or (local-name()='summary' and namespace-uri()='$NsAtom')]"
  content  = "*[local-name()='encoded' or (local-name()='content' and namespace-uri()='$NsAtom')]"
  author   = "*[local-name()='author']/*[local-name()='name']"
  creator  = "*[local-name()='creator' or local-name()='author']"
  category = "*[local-name()='category']"
  media    = ".//*[namespace-uri()='$NsMedia' and (local-name()='content' or local-name()='thumbnail')]"
  enclosure = "*[local-name()='enclosure']"
}

function Get-Text($Node, [string]$XPath) {
  $x = $Node.SelectSingleNode($XPath)
  if ($null -eq $x) { return '' }
  $x.InnerText.Trim()
}

# HTML guardado dentro do feed (descrição, conteúdo). Atom xhtml vem como XML de verdade.
function Get-Markup($Node, [string]$XPath) {
  $x = $Node.SelectSingleNode($XPath)
  if ($null -eq $x) { return '' }
  if ($x.SelectSingleNode('*')) { return $x.InnerXml }
  $x.InnerText
}

# ---------- texto ----------
function ConvertFrom-Html([string]$Html) {
  if (-not $Html) { return '' }
  $h = [regex]::Replace($Html, '(?is)<(script|style|figcaption|iframe|noscript)\b.*?</\1>', ' ')
  $h = [regex]::Replace($h, '(?i)<br\s*/?>|</p>|</div>|</li>|</h\d>|</blockquote>', ' ')
  $h = [regex]::Replace($h, '<[^>]+>', ' ')
  $h = [Net.WebUtility]::HtmlDecode($h)
  # alguns feeds (Nexo) mandam o HTML codificado duas vezes: sobra tag depois da primeira limpeza
  if ($h -match '<[A-Za-z/!][^>]*>') {
    $h = [regex]::Replace($h, '(?is)<(script|style|figcaption|iframe|noscript)\b.*?</\1>', ' ')
    $h = [Net.WebUtility]::HtmlDecode([regex]::Replace($h, '<[^>]+>', ' '))
  }
  [regex]::Replace($h, '\s+', ' ').Trim()
}

# Idioma pelo vocabulário: fontes como o Medium e as revistas acadêmicas misturam línguas.
$LangWords = @{
  pt = 'não são uma você também pelo pela dos das nos nas ao à em um isso ele ela foi seu sua mais quando muito já há até'
  en = 'the and of to is that for with this are from on as by be was his her an it'
  es = 'el los las del por con pero sus está muy y lo su más cuando también'
  fr = 'le les des du est et pour dans qui sur pas au aux ce cette elle sont avec une'
  it = 'della che di gli sono non nel dei delle anche alla più questo uno ed nella'
  id = 'yang dan dengan untuk tidak ini dari akan pada dalam itu adalah bahwa oleh juga cuma tapi bukan sebuah tentang karena sebagai atau bisa lebih kita kami mereka makna iklan'
}
$LangSets = @{}
foreach ($k in $LangWords.Keys) { $LangSets[$k] = New-Object 'Collections.Generic.HashSet[string]' (, [string[]]($LangWords[$k] -split ' ')) }
function Get-Language([string]$Text) {
  $score = @{}
  foreach ($w in ($Text.ToLowerInvariant() -split '[^\p{L}]+')) {
    if (-not $w) { continue }
    foreach ($k in $LangSets.Keys) { if ($LangSets[$k].Contains($w)) { $score[$k] = 1 + [int]$score[$k] } }
  }
  $top = @($score.GetEnumerator() | Sort-Object Value -Descending)
  if (-not $top.Count -or $top[0].Value -lt 3) { return $null }
  if ($top.Count -gt 1 -and $top[0].Value -lt 1.6 * $top[1].Value) { return $null }
  $top[0].Name
}

$Boilerplate = @(
  '(?i)\s*The post .{0,240}? appeared first on .{0,160}$',
  '(?i)\s*O post .{0,240}? apareceu primeiro em .{0,160}$',
  '(?i)\s*\b(Continue reading|Continue lendo|Continuar lendo|Leia mais|Leia a matéria|Read more|Read the full|Leer más|Lire la suite|Leggi tutto|Keep reading)\b.*$',
  '\s*\[(…|\.\.\.)\]\s*$',
  '(?i)^\s*(by|por)\s+[^|]{1,60}\|\s*',
  '(?i)^\s*(this article|este artigo) (was|foi) (originally )?(published|publicado)[^.]{0,120}\.\s*'
)
function Clear-Summary([string]$s) {
  foreach ($p in $Boilerplate) { $s = [regex]::Replace($s, $p, '') }
  $s.Trim()
}

function Limit-Text([string]$s, [int]$n) {
  if (-not $s -or $s.Length -le $n) { return $s }
  $cut = $s.Substring(0, $n)
  $sp = $cut.LastIndexOf(' ')
  if ($sp -gt $n * 0.6) { $cut = $cut.Substring(0, $sp) }
  $cut.TrimEnd(',', ';', ':', '.', ' ', '-', [char]0x2014) + [char]0x2026
}

function Resolve-Url([string]$u, [string]$Base) {
  if (-not $u) { return $null }
  $u = [Net.WebUtility]::HtmlDecode($u.Trim())
  if ($u.StartsWith('//')) { return 'https:' + $u }
  try { return ([Uri]::new([Uri]$Base, $u)).AbsoluteUri } catch { return $null }
}

function Get-CleanUrl([string]$u) {
  $c = [regex]::Replace($u, '([?&])(utm_[^=&]+|fbclid|gclid|mc_cid|mc_eid)=[^&#]*', '$1')
  $c = [regex]::Replace($c, '[?&]+(#|$)', '$1')
  $c -replace '\?&', '?'
}

$Sha = [Security.Cryptography.SHA1]::Create()
function Get-Id([string]$u) {
  $k = ($u -replace '#.*$', '' -replace '^https?://(www\.)?', '' -replace '/+$', '').ToLowerInvariant()
  $b = $Sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($k))
  -join ($b[0..5] | ForEach-Object { $_.ToString('x2') })
}

# ---------- datas (inclui meses em português, espanhol, francês e italiano) ----------
$Months = @{ jan = 1; fev = 2; feb = 2; 'fév' = 2; mar = 3; abr = 4; apr = 4; avr = 4; mai = 5; may = 5; mag = 5; jun = 6; giu = 6; jul = 7; lug = 7; ago = 8; aug = 8; 'aoû' = 8; set = 9; sep = 9; out = 10; oct = 10; ott = 10; nov = 11; dez = 12; dec = 12; 'déc' = 12; dic = 12; ene = 1; gen = 1 }
$Zones = @{ GMT = 0; UTC = 0; UT = 0; Z = 0; EST = -5; EDT = -4; CST = -6; CDT = -5; MST = -7; MDT = -6; PST = -8; PDT = -7; BST = 1; CET = 1; CEST = 2; BRT = -3 }
$DateRx = [regex]'(\d{1,2})\s+([^\s\d,.]+)\.?,?\s+(\d{4})(?:,?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*([+-]\d{2}:?\d{2}|[A-Za-z]{1,4}\b)?'
function ConvertTo-Date([string]$s) {
  if (-not $s) { return $null }
  $m = $DateRx.Match($s.Trim())
  if ($m.Success) {
    $mon = $m.Groups[2].Value.ToLowerInvariant()
    $month = $null
    if ($mon.StartsWith('juin')) { $month = 6 }
    elseif ($mon.StartsWith('juil')) { $month = 7 }
    elseif ($mon.Length -ge 3 -and $Months.ContainsKey($mon.Substring(0, 3))) { $month = $Months[$mon.Substring(0, 3)] }
    if ($month) {
      $h = 0; $mi = 0; $se = 0
      if ($m.Groups[4].Success) { $h = [int]$m.Groups[4].Value; $mi = [int]$m.Groups[5].Value }
      if ($m.Groups[6].Success) { $se = [int]$m.Groups[6].Value }
      $off = [TimeSpan]::Zero
      $tz = $m.Groups[7].Value
      if ($tz -match '^([+-])(\d{2}):?(\d{2})$') {
        $off = New-Object TimeSpan ([int]$Matches[2]), ([int]$Matches[3]), 0
        if ($Matches[1] -eq '-') { $off = $off.Negate() }
      } elseif ($tz -and $Zones.ContainsKey($tz)) { $off = [TimeSpan]::FromHours($Zones[$tz]) }
      try { return (New-Object DateTimeOffset ([int]$m.Groups[3].Value), $month, ([int]$m.Groups[1].Value), $h, $mi, $se, $off).ToUniversalTime() } catch { }
    }
  }
  $dto = [DateTimeOffset]::MinValue
  if ([DateTimeOffset]::TryParse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$dto)) { return $dto.ToUniversalTime() }
  $null
}

# ---------- imagens ----------
$ImgTagRx = [regex]'(?i)<img\b[^>]*>'
$SkipImg = [regex]'(?i)feedburner|/pixel|gravatar\.com|/emoji|smilies|stats\.wordpress|doubleclick|1x1|spacer\.gif|blank\.gif|/icons?/|badge|avatar|tracking|medium\.com/_/stat|\.svg(\?|$)'
function Find-HtmlImage([string]$Html, [string]$Base) {
  if (-not $Html) { return $null }
  foreach ($m in $ImgTagRx.Matches($Html)) {
    $tag = $m.Value
    $src = $null
    foreach ($attr in 'data-src', 'data-lazy-src', 'data-original', 'src') {
      $mm = [regex]::Match($tag, "(?i)\s$attr\s*=\s*[""']([^""']+)[""']")
      if ($mm.Success -and $mm.Groups[1].Value -notmatch '^data:') { $src = $mm.Groups[1].Value; break }
    }
    if (-not $src -or $SkipImg.IsMatch($src)) { continue }
    $w = [regex]::Match($tag, '(?i)\swidth\s*=\s*["'']?(\d+)')
    if ($w.Success -and [int]$w.Groups[1].Value -lt 160) { continue }
    $abs = Resolve-Url $src $Base
    if ($abs) { return $abs }
  }
  $null
}

function Find-FeedImage($Node, [string]$Base) {
  $best = $null; $bestW = -1
  foreach ($m in $Node.SelectNodes($XP.media)) {
    $url = $m.GetAttribute('url')
    if (-not $url -or $SkipImg.IsMatch($url)) { continue }
    $medium = $m.GetAttribute('medium'); $type = $m.GetAttribute('type')
    $isImg = $m.LocalName -eq 'thumbnail' -or $medium -eq 'image' -or $type -like 'image/*' -or $url -match '(?i)\.(jpe?g|png|webp|gif|avif)(\?|$)'
    if (-not $isImg) { continue }
    $w = 0; [void][int]::TryParse($m.GetAttribute('width'), [ref]$w)
    if ($m.LocalName -eq 'content') { $w += 1 }
    if ($w -gt $bestW) { $best = $url; $bestW = $w }
  }
  if ($best) { return Resolve-Url $best $Base }
  foreach ($e in $Node.SelectNodes($XP.enclosure)) {
    $url = $e.GetAttribute('url')
    if ($url -and ($e.GetAttribute('type') -like 'image/*' -or $url -match '(?i)\.(jpe?g|png|webp|gif|avif)(\?|$)')) { return Resolve-Url $url $Base }
  }
  $null
}

$MetaRx = [regex]'(?i)<meta\b[^>]*>'
$OgRx = [regex]'(?i)(property|name)\s*=\s*["''](og:image(:secure_url|:url)?|twitter:image(:src)?)["'']'
$ContentRx = [regex]'(?i)\scontent\s*=\s*["'']([^"'']+)["'']'
function Find-PageImage([string]$Html, [string]$Base) {
  $headEnd = $Html.IndexOf('</head>', [StringComparison]::OrdinalIgnoreCase)
  if ($headEnd -gt 0) { $Html = $Html.Substring(0, $headEnd) }
  foreach ($m in $MetaRx.Matches($Html)) {
    if (-not $OgRx.IsMatch($m.Value)) { continue }
    $c = $ContentRx.Match($m.Value)
    if ($c.Success -and -not $SkipImg.IsMatch($c.Groups[1].Value)) { return Resolve-Url $c.Groups[1].Value $Base }
  }
  $null
}

# ---------- leitura de cada matéria ----------
function Read-Item($Node, $Src) {
  $title = ConvertFrom-Html (Get-Text $Node $XP.title)
  if (-not $title) { return $null }

  $link = Get-Text $Node $XP.origLink
  if (-not $link) { $a = $Node.SelectSingleNode($XP.atomLink); if ($null -ne $a) { $link = $a.GetAttribute('href') } }
  if (-not $link) { $link = Get-Text $Node $XP.link }
  if (-not $link) {
    $g = $Node.SelectSingleNode($XP.guid)
    if ($null -ne $g -and $g.InnerText.Trim() -match '^https?://' -and $g.GetAttribute('isPermaLink') -ne 'false') { $link = $g.InnerText.Trim() }
  }
  $link = Resolve-Url $link $Src.site
  if (-not $link) { return $null }
  $link = Get-CleanUrl $link

  $date = $null
  foreach ($name in 'pubDate', 'published', 'date', 'issued', 'updated') {
    $s = Get-Text $Node "*[local-name()='$name']"
    if ($s) { $date = ConvertTo-Date $s; if ($date) { break } }
  }

  $descHtml = Get-Markup $Node $XP.desc
  $bodyHtml = Get-Markup $Node $XP.content
  $summary = Clear-Summary (ConvertFrom-Html $descHtml)
  $bodyText = ConvertFrom-Html $bodyHtml
  if ((-not $summary -or $summary -eq $title) -and $bodyText) { $summary = Clear-Summary $bodyText }
  if ($summary -eq $title) { $summary = '' }

  $minutes = $null
  if ($bodyText.Length -gt 1500) { $minutes = [int][Math]::Max(1, [Math]::Round(($bodyText -split ' ').Count / 200)) }

  $img = Find-FeedImage $Node $link
  if (-not $img) { $img = Find-HtmlImage ($bodyHtml + ' ' + $descHtml) $link }
  if ($img) { $img = $img -replace '^http://', 'https://' }

  $author = Get-Text $Node $XP.author
  if (-not $author) { $author = Get-Text $Node $XP.creator }
  if ($author -match '@' -and $author -match '\(([^)]+)\)') { $author = $Matches[1] }
  if ($author -match '@') { $author = '' }

  $cats = @($Node.SelectNodes($XP.category) | ForEach-Object { if ($_.InnerText) { $_.InnerText } else { $_.GetAttribute('term') } })

  [ordered]@{
    id = Get-Id $link; s = $Src.id; u = $link
    t = Limit-Text $title 220; d = Limit-Text $summary 320
    tt = $null; td = $null; img = $img
    at = $(if ($date) { $date.ToString('o') } else { $null }); fs = $null
    au = Limit-Text $author 80; tg = @(); l = $Src.lang; m = $minutes; ix = $null
    cats = ($cats -join ' ')
  }
}

# ---------- tradução ----------
# Google (gratuito, sem chave) em lotes; se bloquear, MyMemory só para os títulos.
function Invoke-Google([string[]]$Texts, [string]$From) {
  $q = ($Texts | ForEach-Object { $_ -replace '[\r\n]+', ' ' }) -join "`n"
  $url = 'https://translate.googleapis.com/translate_a/single?client=gtx&sl=' + $From + '&tl=pt&dt=t&q=' + [Uri]::EscapeDataString($q)
  $resp = $script:Http.GetAsync($url).GetAwaiter().GetResult()
  if (-not $resp.IsSuccessStatusCode) { throw "Google respondeu $([int]$resp.StatusCode)" }
  $data = ConvertFrom-Json ($resp.Content.ReadAsStringAsync().GetAwaiter().GetResult())
  $sb = New-Object Text.StringBuilder
  foreach ($seg in $data[0]) { if ($seg -and $seg[0]) { [void]$sb.Append([string]$seg[0]) } }
  $parts = @($sb.ToString() -split "`n" | ForEach-Object { $_.Trim() })
  if ($parts.Count -ne $Texts.Count) { throw "Google devolveu $($parts.Count) partes para $($Texts.Count)" }
  $parts
}

function Invoke-MyMemory([string]$Text, [string]$From) {
  $url = 'https://api.mymemory.translated.net/get?q=' + [Uri]::EscapeDataString((Limit-Text $Text 450)) + '&langpair=' + $From + '%7Cpt-BR'
  $d = ConvertFrom-Json ($script:Http.GetStringAsync($url).GetAwaiter().GetResult())
  if ($d.quotaFinished -or [int]$d.responseStatus -ne 200) { throw "MyMemory: $($d.responseDetails)" }
  [Net.WebUtility]::HtmlDecode([string]$d.responseData.translatedText)
}

function Add-Translations($Items) {
  $todo = @($Items | Where-Object { $_.l -ne 'pt' -and -not $_.tt })
  if (-not $todo.Count) { return }
  $google = $true; $memBudget = 4500; $done = 0
  foreach ($lang in @($todo | ForEach-Object { $_.l } | Sort-Object -Unique)) {
    $group = @($todo | Where-Object { $_.l -eq $lang })
    $i = 0
    while ($i -lt $group.Count) {
      if ($google) {
        # lote de até ~1500 caracteres: título e resumo de cada matéria, uma linha cada
        $batch = @(); $size = 0
        while ($i -lt $group.Count -and ($batch.Count -eq 0 -or $size + $group[$i].t.Length + ([string]$group[$i].d).Length -lt 1500)) {
          $batch += $group[$i]; $size += $group[$i].t.Length + ([string]$group[$i].d).Length; $i++
        }
        $texts = @(); foreach ($it in $batch) { $texts += $it.t; $texts += $(if ($it.d) { $it.d } else { '.' }) }
        try {
          $res = @(Invoke-Google $texts $lang)
          for ($k = 0; $k -lt $batch.Count; $k++) {
            $batch[$k].tt = $res[2 * $k]
            if ($batch[$k].d) { $batch[$k].td = $res[2 * $k + 1] }
          }
          $done += $batch.Count
          Start-Sleep -Milliseconds 350
        } catch {
          Write-Host "  tradução: $($_.Exception.Message); seguindo com MyMemory só nos títulos"
          $google = $false
          $i -= $batch.Count
        }
      } else {
        if ($memBudget -le 0) { break }
        $it = $group[$i]; $i++
        try { $it.tt = Invoke-MyMemory $it.t $lang; $memBudget -= $it.t.Length; $done++ }
        catch { Write-Host "  tradução: $($_.Exception.Message)"; $memBudget = 0 }
      }
    }
  }
  Write-Host "Traduzidas: $done de $($todo.Count) matérias de fora"
}

# ---------- coleta ----------
$cfg = Get-Content -Raw -Encoding UTF8 $Sources | ConvertFrom-Json
$srcList = @($cfg.sources)
$srcById = @{}; foreach ($s in $srcList) { $srcById[$s.id] = $s }
$now = [DateTimeOffset]::UtcNow
$nowIso = $now.ToString('o')

$prev = @{}
if (Test-Path $Out) {
  try {
    $old = Get-Content -Raw -Encoding UTF8 $Out | ConvertFrom-Json
    foreach ($o in $old.items) {
      $h = [ordered]@{}
      foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }
      $h.tg = @($h.tg)
      # o pwsh 7 transforma texto de data em DateTime ao ler JSON: volta para ISO
      foreach ($k in 'at', 'fs') { if ($h[$k] -is [DateTime]) { $h[$k] = ([DateTimeOffset]([DateTime]$h[$k]).ToUniversalTime()).ToString('o') } }
      $prev[$h.id] = $h
    }
  } catch { Write-Warning "Não deu para ler o feed anterior: $($_.Exception.Message)" }
}

Write-Host "Buscando $($srcList.Count) fontes..."
$fetched = Get-Many @($srcList | ForEach-Object { $_.url }) $script:Http
$status = @{}
$fresh = [ordered]@{}
foreach ($src in $srcList) {
  $r = $fetched[$src.url]
  if ($r.err) { $status[$src.id] = $r.err; Write-Host ("  x {0,-22} {1}" -f $src.id, $r.err); continue }
  try {
    $doc = Read-Feed (ConvertTo-Text $r.bytes $r.charset)
    $n = 0
    foreach ($node in $doc.SelectNodes("//*[local-name()='item' or local-name()='entry']")) {
      $it = Read-Item $node $src
      if ($it -and -not $fresh.Contains($it.id)) { $fresh[$it.id] = $it; $n++ }
    }
    $status[$src.id] = 'ok'
    Write-Host ("  ok {0,-21} {1} itens" -f $src.id, $n)
  } catch {
    $status[$src.id] = $_.Exception.Message
    Write-Host ("  x {0,-22} {1}" -f $src.id, $_.Exception.Message)
  }
}

$okCount = @($status.Values | Where-Object { $_ -eq 'ok' }).Count
if ($okCount -lt [Math]::Ceiling($srcList.Count * 0.3)) { throw "Só $okCount fontes responderam; mantendo o feed anterior." }

# junta com o que já existia: guarda tradução, imagem e a primeira vez que vimos cada matéria
$pool = New-Object Collections.ArrayList
foreach ($it in $fresh.Values) {
  $p = $prev[$it.id]
  if ($p) {
    $it.fs = $p.fs
    if ($p.t -eq $it.t) { $it.tt = $p.tt }
    if ($p.d -eq $it.d) { $it.td = $p.td }
    if (-not $it.img -and $p.img) { $it.img = $p.img }
    $it.ix = $p.ix
  } else { $it.fs = $nowIso }
  [void]$pool.Add($it)
}
foreach ($p in $prev.Values) {
  if (-not $fresh.Contains($p.id) -and $srcById.ContainsKey($p.s)) { $p.cats = ''; [void]$pool.Add($p) }
}

# janela de tempo, filtro de tema, limite por fonte e duplicadas
$kept = New-Object Collections.ArrayList
$seenTitles = @{}
foreach ($grp in ($pool | Group-Object { $_.s })) {
  $src = $srcById[$grp.Name]
  $days = if ($src.days) { [int]$src.days } elseif ($src.kind -eq 'academia') { 180 } else { 21 }
  $max = if ($src.max) { [int]$src.max } elseif ($src.kind -eq 'academia') { 5 } else { 12 }
  $cut = $now.AddDays(-$days)
  $cands = @()
  foreach ($it in $grp.Group) {
    if (-not $it.at) { $it.at = $it.fs }
    $at = ConvertTo-Date $it.at
    if (-not $at) { continue }
    if ($at -gt $now.AddHours(1)) { $at = $now; $it.at = $nowIso }
    if ($at -lt $cut) { continue }
    $lang = Get-Language "$($it.t) $($it.d)"
    if ($lang -eq 'id') { continue }
    if ($lang) { $it.l = $lang }
    if ($src.filter -and -not $FilterRx.IsMatch($it.t) -and @($FilterRx.Matches("$($it.d)") | ForEach-Object { $_.Value.ToLowerInvariant() } | Sort-Object -Unique).Count -lt 2) { continue }
    $it.tg = (Get-Tags ("$($it.t) $($it.d) $($it.tt) $($it.td) $($it.cats)") $src "$($it.t) $($it.tt)").tags
    $cands += , @{ it = $it; at = $at }
  }
  foreach ($c in @($cands | Sort-Object { $_.at } -Descending | Select-Object -First $max)) {
    $tk = ($c.it.t.ToLowerInvariant() -replace '[^\p{L}\p{N}]', '')
    if ($tk.Length -gt 80) { $tk = $tk.Substring(0, 80) }
    if ($seenTitles.ContainsKey($tk)) { continue }
    $seenTitles[$tk] = 1
    [void]$kept.Add($c.it)
  }
}

# imagem da página (og:image) para quem veio sem foto
if (-not $NoImages) {
  $need = @($kept | Where-Object { -not $_.img -and -not $_.ix -and $srcById[$_.s].kind -ne 'academia' } | Select-Object -First 120)
  if ($need.Count) {
    Write-Host "Procurando imagem na página de $($need.Count) matérias..."
    $pages = Get-Many @($need | ForEach-Object { $_.u }) $script:PageHttp
    $found = 0
    foreach ($it in $need) {
      $it.ix = 1
      $r = $pages[$it.u]
      if (-not $r -or $r.err) { continue }
      $len = [Math]::Min($r.bytes.Length, 400000)
      $html = [Text.Encoding]::UTF8.GetString($r.bytes, 0, $len)
      $img = Find-PageImage $html $it.u
      if ($img) { $it.img = $img -replace '^http://', 'https://'; $found++ }
    }
    Write-Host "  achou $found imagens"
  }
}

if (-not $NoTranslate) {
  Add-Translations $kept
  # com a tradução, os temas das matérias de fora ficam mais certeiros
  foreach ($it in $kept) {
    if ($it.l -ne 'pt' -and $it.tt) { $it.tg = (Get-Tags ("$($it.t) $($it.d) $($it.tt) $($it.td) $($it.cats)") $srcById[$it.s] "$($it.t) $($it.tt)").tags }
  }
}

# ---------- gravação ----------
$items = @($kept | Sort-Object { $_.at } -Descending | ForEach-Object {
  $o = [ordered]@{}
  foreach ($k in 'id', 's', 'u', 't', 'd', 'tt', 'td', 'img', 'at', 'fs', 'au', 'tg', 'l', 'm', 'ix') {
    $v = $_[$k]
    if ($null -eq $v -or ($v -is [string] -and $v -eq '')) { continue }
    if ($k -eq 'tg') { $v = @($v) }
    $o[$k] = $v
  }
  $o
})

$counts = @{}; foreach ($it in $items) { $counts[$it.s] = 1 + [int]$counts[$it.s] }
$feed = [ordered]@{
  v = 1
  updated = $nowIso
  tags = @($TagRules | ForEach-Object { [ordered]@{ id = $_.id; label = $_.label } })
  sources = @($srcList | ForEach-Object {
    [ordered]@{ id = $_.id; name = $_.name; site = $_.site; lang = $_.lang; kind = $(if ($_.kind) { $_.kind } else { 'mag' }); tags = @($_.tags); w = $(if ($_.w) { $_.w } else { 0 }); n = [int]$counts[$_.id]; ok = ($status[$_.id] -eq 'ok') }
  })
  items = $items
}

New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$json = ConvertTo-Json $feed -Depth 6 -Compress
[IO.File]::WriteAllText($Out, $json, (New-Object Text.UTF8Encoding $false))
$langs = ($items | Group-Object { $_.l } | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' '
Write-Host "Feed gravado: $($items.Count) matérias de $okCount/$($srcList.Count) fontes ($langs) -> $Out"
