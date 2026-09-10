param([string]$RepoRoot = "")
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }
$aliasesPath = Join-Path $RepoRoot "asset-catalog\aliases.csv"
$imagesRoot = Join-Path $RepoRoot "Imagens Ilustrativa"

function Normalize-Key([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
  $text = $Value.Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object Text.StringBuilder
  foreach ($ch in $text.ToCharArray()) {
    if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
  }
  $text = $sb.ToString().Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
  $text = $text -replace '&',' e ' -replace '[_\-]+',' ' -replace '[^\p{L}\p{Nd}]+',' ' -replace '\s+',' '
  return $text.Trim()
}

$targetMap = @{
  'Cachorro.png'='animal-dog-cachorro.png'; 'Borracha.png'='school-object-eraser-borracha.png'; 'Caneta azul.png'='school-object-blue-pen-caneta-azul.png';
  'Cavalo.png'='animal-horse-cavalo.png'; 'Boy.png'='person-boy-menino.png'; 'Girl.png'='person-girl-menina.png'; 'Hello.png'='greeting-hello-oi.png';
  'Bye.png'='greeting-goodbye-tchau.png'; 'Good Morning.png'='greeting-good-morning-bom-dia.png'; 'Good Afternoon.png'='greeting-good-afternoon-boa-tarde.png'; 'Good Night.png'='greeting-good-night-boa-noite.png';
  'Almoçando.png'='routine-have-lunch-almocar.png'; 'Cachorro dentro da caixa.png'='spatial-dog-cachorro-inside-box.png'; 'Cachorro embaixo da mesa.png'='spatial-dog-cachorro-under-table.png';
  'Cama ao lado do guarda-roupa marrom.png'='spatial-bed-next-brown-wardrobe.png'; 'Caminhão preto atrás do ônibus.png'='spatial-black-truck-behind-bus.png'; 'Coelho.png'='animal-rabbit-coelho.png';
  'Em pé.png'='classroom-command-stand-up-em-pe.png'; 'Escovando os dentes.png'='routine-brush-teeth-escovar-dentes.png'; 'Estojo rosa.png'='school-object-pink-pencil-case-estojo-rosa.png';
  'Estojo.png'='school-object-pencil-case-estojo.png'; 'Fish_Girl.png'='person-girl-with-fish-menina-com-peixe.png'; 'Gato.png'='animal-cat-gato.png';
  'Giz de cera laranja.png'='school-object-orange-crayon-giz-laranja.png'; 'Giz de cera vermelho.png'='school-object-red-crayon-giz-vermelho.png'; 'Hamister.png'='animal-hamster.png';
  'Letra A - EI.png'='letter-a-pronunciation-ei.png'; 'Letra B - BI.png'='letter-b-pronunciation-bi.png'; 'Letra C - SI.png'='letter-c-pronunciation-si.png';
  'Letra D - DI.png'='letter-d-pronunciation-di.png'; 'Letra E - I.png'='letter-e-pronunciation-i.png'; 'Letra M - EM.png'='letter-m-pronunciation-em.png'; 'Letra S - ES.png'='letter-s-pronunciation-es.png';
  'Lápis azul.png'='school-object-blue-pencil-lapis-azul.png'; 'Lápis vermelho.png'='school-object-red-pencil-lapis-vermelho.png'; 'Lápis.png'='school-object-pencil-lapis.png';
  'Mochila ao lado da cadeira.png'='spatial-backpack-next-chair.png'; 'Mochila vermelha e amarela.png'='school-object-red-yellow-backpack-mochila-vermelha-amarela.png'; 'Mochila.png'='school-object-backpack-mochila.png';
  'My name.png'='introduction-my-name-meu-nome.png'; 'Ovelha.png'='animal-sheep-ovelha.png'; 'Passáro.png'='animal-bird-passaro.png'; 'Pato.png'='animal-duck-pato.png'; 'Peixe.png'='animal-fish-peixe.png';
  'Porco.png'='animal-pig-porco.png'; 'Rain.png'='weather-rain-chuva.png'; 'Régua.png'='school-object-ruler-regua.png'; 'Sentada.png'='classroom-command-sit-down-sentar.png';
  'Silêncio.png'='classroom-command-quiet-silencio.png'; 'TV sobre a mesa.png'='spatial-tv-on-table.png'; 'Tapete embaixo do guarda-roupa.png'='spatial-rug-under-wardrobe.png'; 'Tartaruga.png'='animal-turtle-tartaruga.png';
  'Tocando as mãos.png'='body-part-touch-hands-tocar-maos.png'; 'Tocando na cabeça.png'='body-part-touch-head-tocar-cabeca.png'; 'Tocando os braços.png'='body-part-touch-arms-tocar-bracos.png';
  'Tocando os joelhos.png'='body-part-touch-knees-tocar-joelhos.png'; 'Tocando os pés.png'='body-part-touch-feet-tocar-pes.png'; 'Vaca.png'='animal-cow-vaca.png';
  'Veterinário cuidando de um animal.png'='profession-veterinarian-veterinario-animal-care.png'; 'acordando.png'='routine-wake-up-acordar.png'; 'brincando.png'='routine-play-brincar.png';
  'descansando.png'='routine-rest-descansar.png'; 'desenhando.png'='routine-draw-desenhar.png'; 'desenhando no parque.png'='routine-draw-park-desenhar-parque.png';
  'indo dormir.png'='routine-go-to-sleep-ir-dormir.png'; 'indo para a escola.png'='routine-go-to-school-ir-para-escola.png'; 'lendo.png'='routine-read-ler.png';
  'nervous.png'='emotion-nervous-nervoso.png'; 'wheelchair_boy.png'='person-wheelchair-boy-menino-cadeirante.png'
}

$rows = @(Import-Csv $aliasesPath -Encoding UTF8)
$byAlias = [ordered]@{}
foreach ($row in $rows) {
  $key = Normalize-Key ([string]$row.alias)
  if (-not $key) { continue }
  $target = [string]$row.target
  if ($targetMap.ContainsKey($target)) { $target = [string]$targetMap[$target] }
  $byAlias[$key] = [pscustomobject][ordered]@{ alias=[string]$row.alias; target=$target; category=[string]$row.category; notes=[string]$row.notes }
}

function Add-Alias([string]$Alias,[string]$Target,[string]$Category,[string]$Notes='Canonical semantic alias') {
  $key = Normalize-Key $Alias
  if (-not $key) { return }
  $byAlias[$key] = [pscustomobject][ordered]@{ alias=$Alias; target=$Target; category=$Category; notes=$Notes }
}

$extra = @(
  @('cachorro','animal-dog-cachorro.png','animals'), @('cat','animal-cat-gato.png','animals'), @('gato','animal-cat-gato.png','animals'), @('rabbit','animal-rabbit-coelho.png','animals'), @('coelho','animal-rabbit-coelho.png','animals'),
  @('bird','animal-bird-passaro.png','animals'), @('passaro','animal-bird-passaro.png','animals'), @('fish','animal-fish-peixe.png','animals'), @('peixe','animal-fish-peixe.png','animals'), @('cow','animal-cow-vaca.png','animals'), @('vaca','animal-cow-vaca.png','animals'),
  @('duck','animal-duck-pato.png','animals'), @('pato','animal-duck-pato.png','animals'), @('horse','animal-horse-cavalo.png','animals'), @('cavalo','animal-horse-cavalo.png','animals'), @('pig','animal-pig-porco.png','animals'), @('porco','animal-pig-porco.png','animals'), @('sheep','animal-sheep-ovelha.png','animals'), @('ovelha','animal-sheep-ovelha.png','animals'),
  @('animal turtle','animal-turtle-tartaruga.png','animals'), @('animal tartaruga','animal-turtle-tartaruga.png','animals'), @('big cat','animal-cat-gato-big-grande.png','animals'), @('gato grande','animal-cat-gato-big-grande.png','animals'), @('small cat','animal-cat-gato-small-pequeno.png','animals'), @('gato pequeno','animal-cat-gato-small-pequeno.png','animals'), @('big dog','animal-dog-cachorro-big-grande.png','animals'), @('cachorro grande','animal-dog-cachorro-big-grande.png','animals'), @('small dog','animal-dog-cachorro-small-pequeno.png','animals'), @('cachorro pequeno','animal-dog-cachorro-small-pequeno.png','animals'),
  @('father','family-father-pai.png','family'), @('pai','family-father-pai.png','family'), @('grandmother','family-grandmother-avo-feminino.png','family'), @('avo feminino','family-grandmother-avo-feminino.png','family'), @('family sister','family-sister-irma.png','family'), @('family brother','family-brother-irmao.png','family'), @('family mother','family-mother-mae.png','family'), @('family grandfather','family-grandfather-avo-masculino.png','family'),
  @('toy kite','toy-kite-pipa.png','toy'), @('blue ball','toy-ball-bola-blue-azul.png','toy'), @('bola azul','toy-ball-bola-blue-azul.png','toy'), @('doll','toy-doll-boneca.png','toy'), @('boneca','toy-doll-boneca.png','toy'), @('red boat','toy-boat-barco-red-vermelho.png','toy'), @('barco vermelho','toy-boat-barco-red-vermelho.png','toy'), @('teddy bear','toy-teddy-bear-urso-pelucia.png','toy'), @('urso de pelucia','toy-teddy-bear-urso-pelucia.png','toy'), @('video game','toy-video-game.png','toy'),
  @('bus','transport-bus-onibus.png','transport'), @('onibus','transport-bus-onibus.png','transport'), @('car','transport-car-carro.png','transport'), @('carro','transport-car-carro.png','transport'), @('plane','transport-plane-aviao.png','transport'), @('aviao','transport-plane-aviao.png','transport'), @('train','transport-train-trem.png','transport'), @('trem','transport-train-trem.png','transport'), @('truck','transport-truck-caminhao.png','transport'), @('caminhao','transport-truck-caminhao.png','transport'),
  @('lapis','school-object-pencil-lapis.png','school'), @('regua','school-object-ruler-regua.png','school'), @('mochila','school-object-backpack-mochila.png','school'), @('estojo','school-object-pencil-case-estojo.png','school'),
  @('amarelo','color-yellow-amarelo.png','colors'), @('azul','color-blue-azul.png','colors'), @('preto','color-black-preto.png','colors'), @('rosa','color-pink-rosa.png','colors'), @('verde','color-green-verde.png','colors'), @('vermelho','color-red-vermelho.png','colors'), @('laranja','color-orange-laranja.png','colors'), @('branco','color-white-branco.png','colors'), @('marrom','color-brown-marrom.png','colors'),
  @('children greeting','scene-children-greeting.png','scene'), @('criancas se cumprimentando','scene-children-greeting.png','scene'), @('welcome new student','scene-school-welcome-new-student.png','scene'), @('acolhida aluno novo','scene-school-welcome-new-student.png','scene'), @('school arrival morning','scene-school-arrival-morning.png','scene'), @('chegada escola manha','scene-school-arrival-morning.png','scene'), @('end of class','scene-class-end.png','scene'), @('fim da aula','scene-class-end.png','scene'), @('school exit','scene-school-exit.png','scene'), @('saida da escola','scene-school-exit.png','scene'),
  @('dog in the box','spatial-dog-cachorro-inside-box.png','spatial'), @('cachorro dentro da caixa','spatial-dog-cachorro-inside-box.png','spatial'), @('dog under the table','spatial-dog-cachorro-under-table.png','spatial'), @('cachorro embaixo da mesa','spatial-dog-cachorro-under-table.png','spatial'), @('backpack next to chair','spatial-backpack-next-chair.png','spatial'), @('mochila ao lado da cadeira','spatial-backpack-next-chair.png','spatial'), @('tv on the table','spatial-tv-on-table.png','spatial'), @('tv sobre a mesa','spatial-tv-on-table.png','spatial'), @('rug under the wardrobe','spatial-rug-under-wardrobe.png','spatial'), @('tapete embaixo do guarda roupa','spatial-rug-under-wardrobe.png','spatial'),
  @('profile:maya','character-maya.png','year3'), @('profile:maya:9','character-maya.png','year3'), @('profile:maya:10','character-maya.png','year3'), @('profile:ana','character-ana.png','year3'), @('profile:ana:12','character-ana.png','year3'),
  @('three small circles','y3-three-small-circles.png','year3'), @('two yellow stars','y3-two-yellow-stars.png','year3'), @('five small stars','y3-five-small-stars.png','year3'), @('six blue rectangles','y3-six-blue-rectangles.png','year3'), @('2 big hands','y3-two-big-hands.png','year3'), @('2 green eyes','y3-two-green-eyes.png','year3')
)
foreach ($entry in $extra) { Add-Alias $entry[0] $entry[1] $entry[2] }

$en = @('','one','two','three','four','five','six','seven','eight','nine','ten','eleven','twelve','thirteen','fourteen','fifteen','sixteen','seventeen','eighteen','nineteen','twenty')
$pt = @('','um','dois','tres','quatro','cinco','seis','sete','oito','nove','dez','onze','doze','treze','quatorze','quinze','dezesseis','dezessete','dezoito','de