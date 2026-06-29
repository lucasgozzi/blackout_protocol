# Blackout Protocol — Asset Generation Prompts

## CONCEITO CORRETO

Cada **tile** é uma **peça grande do tabuleiro** — como no Zombicide.
Um tile representa um espaço completo: uma rua inteira, uma sala, uma praça.
O mapa é montado juntando vários tiles lado a lado.

**Tamanho de cada tile: 1024×1024px**
Formato: PNG, sem fundo transparente (tiles têm fundo sólido).
Estilo: top-down realista, sci-fi pós-apocalíptico, escuro, detalhado.

Dentro de cada tile existem **zonas** (áreas navegáveis) — mas isso é definido
no código, não na imagem. A imagem é só o visual do tile inteiro.

---

## TILES DO MAPA

---

### `tile_lab.png` — Laboratório / Sala interior

Tile grande representando um laboratório abandonado visto de cima.
```
top-down battle map tile, large abandoned sci-fi laboratory room,
viewed directly from above, 1024x1024, realistic tabletop RPG style,
dark concrete floor with worn tiles, broken lab benches along walls,
scattered equipment and broken screens, emergency red lighting strips,
dust and debris on floor, two doorway openings on opposite walls
(north and east sides), thick reinforced concrete walls on other sides,
no characters, professional digital art, high detail
```

---

### `tile_corridor.png` — Corredor

Tile grande representando um corredor industrial longo.
```
top-down battle map tile, long industrial corridor viewed from above,
1024x1024, realistic tabletop RPG style, dark metal grating floor,
pipes and cables running along walls, flickering emergency lights,
openings on left and right ends connecting to other areas,
solid walls on top and bottom, debris scattered, 
no characters, professional digital art, high detail
```

---

### `tile_street_ns.png` — Rua (Norte-Sul)

Tile grande representando uma rua urbana abandonada, eixo norte-sul.
```
top-down battle map tile, abandoned city street viewed from above,
1024x1024, realistic tabletop RPG style, north-south orientation,
cracked dark asphalt with faded yellow center lines, 
broken sidewalks on left and right sides with overgrown weeds,
abandoned cars, trash and debris, 
open ends on north and south for movement between tiles,
buildings blocking east and west sides,
no characters, professional digital art, high detail
```

---

### `tile_street_ew.png` — Rua (Leste-Oeste)

Tile grande representando uma rua urbana abandonada, eixo leste-oeste.
```
top-down battle map tile, abandoned city street viewed from above,
1024x1024, realistic tabletop RPG style, east-west orientation,
cracked dark asphalt with faded white lane markings,
broken sidewalks on top and bottom sides,
abandoned vehicles, scattered debris and broken glass,
open ends on east and west for movement between tiles,
buildings blocking north and south sides,
no characters, professional digital art, high detail
```

---

### `tile_crossroads.png` — Cruzamento

Tile grande representando um cruzamento urbano.
```
top-down battle map tile, abandoned city crossroads intersection
viewed from above, 1024x1024, realistic tabletop RPG style,
cracked asphalt with faded traffic markings at center,
openings on all four sides (north south east west),
overturned car in one corner, broken traffic lights fallen,
debris and overgrown weeds in sidewalk corners,
post-apocalyptic atmosphere, no characters,
professional digital art, high detail
```

---

### `tile_plaza.png` — Praça Aberta

Tile grande representando uma praça urbana aberta.
```
top-down battle map tile, abandoned city plaza viewed from above,
1024x1024, realistic tabletop RPG style,
large open concrete area with cracked pavement,
destroyed fountain or statue at center, scattered benches,
weeds growing through cracks, debris everywhere,
openings on three sides connecting to streets,
one side has a ruined building facade wall,
dark atmospheric lighting, no characters,
professional digital art, high detail
```

---

### `tile_garage.png` — Garagem / Depósito

Tile grande representando uma garagem ou depósito industrial.
```
top-down battle map tile, abandoned industrial garage or warehouse
viewed from above, 1024x1024, realistic tabletop RPG style,
large open floor space with oil stains and tire marks,
metal shelving units along walls with scattered boxes,
one large vehicle bay door opening on one side,
one personnel door opening on another side,
thick walls on remaining sides, dark interior,
no characters, professional digital art, high detail
```

---

### `tile_fuel_depot.png` — Depósito de Combustível ⭐ Objetivo

Tile grande representando um depósito de combustível — contém os canisters.
```
top-down battle map tile, abandoned fuel depot storage room
viewed from above, 1024x1024, realistic tabletop RPG style,
industrial floor with fuel stains and warning markings,
large cylindrical fuel canisters stacked against walls (glowing faintly),
fuel tanks and pipes visible, caution stripe floor markings,
one entrance door on south side, emergency lighting,
objective items clearly visible, no characters,
professional digital art, high detail
```

---

### `tile_server_room.png` — Sala de Servidores

Tile grande representando uma sala de servidores de IA.
```
top-down battle map tile, abandoned AI server room viewed from above,
1024x1024, realistic tabletop RPG style,
rows of server racks with blinking lights still active,
raised floor panels, thick cables everywhere,
cold blue-green ambient light from screens,
one security door opening on one side,
walls with server equipment on three sides,
eerie atmosphere, no characters,
professional digital art, high detail
```

---

### `tile_extraction.png` — Zona de Extração ⭐ Saída

Tile grande representando a zona de extração — saída da missão.
```
top-down battle map tile, emergency extraction zone viewed from above,
1024x1024, realistic tabletop RPG style,
large helicopter landing pad on rooftop or open lot,
glowing green circle painted on dark surface with EXTRACTION text,
emergency flares lit around perimeter, debris pushed to sides,
open to sky, grating or concrete floor,
pulsing green extraction marker clearly visible,
no characters, professional digital art, high detail
```

---

## PERSONAGENS — PORTRAIT (Tela de Seleção)

**Tamanho: 1024×1024px**
Estilo: anime high quality, busto, fundo escuro dramático.
Usado na tela de seleção de operadores.

---

### `scout_aria_portrait.png`
```
anime game character full portrait, female scout operator named Aria,
short silver-white hair with undercut, single cyberpunk tactical
visor over left eye with green HUD glow, black skintight bodysuit
with subtle green circuit line patterns, athletic lean build,
serious focused expression, half-body shot with weapon holstered,
dramatic dark background with green energy particles and light rays,
high quality anime illustration, game character art style,
vibrant colors, highly detailed
```

---

### `engineer_rex_portrait.png`
```
anime game character full portrait, male engineer operator named Rex,
close-cropped dark military hair, prominent cybernetic left arm
with orange glowing hydraulic joints, olive tactical vest
with tool pouches and gadgets, utility belt, goggles on forehead,
determined gruff expression, half-body shot with wrench or device,
dramatic dark background with orange mechanical sparks,
high quality anime illustration, game character art style,
vibrant colors, highly detailed
```

---

### `medic_nova_portrait.png`
```
anime game character full portrait, female medic operator named Nova,
long purple hair tied back practically, white tactical medical coat
with blue glowing cross emblem on chest, medical scanner device
in one hand, calm composed intelligent expression,
half-body shot, dramatic dark background with cool blue ambient light
and floating medical holographic displays,
high quality anime illustration, game character art style,
vibrant colors, highly detailed
```

---

### `soldier_kai_portrait.png`
```
anime game character full portrait, male soldier operator named Kai,
military buzz cut dark hair, heavy black tactical power armor
with red glowing accent lines and joint illumination,
battle helmet clipped to belt, stern battle-hardened expression,
holding large tactical rifle, half-body shot,
dramatic dark background with red energy and explosions behind,
high quality anime illustration, game character art style,
vibrant colors, highly detailed
```

---

## PERSONAGENS — TOKEN (Miniatura no Tabuleiro)

**Tamanho: 256×256px, fundo transparente**
Representa a peça física no tabuleiro.
Deve ser reconhecível em tamanho pequeno (40×40px no board).
Formato: círculo com borda colorida por operador.

---

### `scout_aria_token.png` — borda verde
```
circular tabletop game token, top-down miniature token style,
female cyberpunk scout character portrait from above at slight angle,
silver white hair, green glowing visor, black bodysuit visible,
inside a clean dark circle with bright green neon border ring,
transparent background outside circle, bold readable design,
professional board game token art, works at small sizes
```

---

### `engineer_rex_token.png` — borda laranja
```
circular tabletop game token, top-down miniature token style,
male engineer character portrait from above at slight angle,
dark hair, orange cybernetic arm, olive vest visible,
inside a clean dark circle with bright orange neon border ring,
transparent background outside circle, bold readable design,
professional board game token art, works at small sizes
```

---

### `medic_nova_token.png` — borda azul
```
circular tabletop game token, top-down miniature token style,
female medic character portrait from above at slight angle,
purple hair, white coat, blue medical cross emblem,
inside a clean dark circle with bright blue neon border ring,
transparent background outside circle, bold readable design,
professional board game token art, works at small sizes
```

---

### `soldier_kai_token.png` — borda vermelha
```
circular tabletop game token, top-down miniature token style,
male soldier character portrait from above at slight angle,
buzz cut, black heavy armor, red accent lines,
inside a clean dark circle with bright red neon border ring,
transparent background outside circle, bold readable design,
professional board game token art, works at small sizes
```

---

## INIMIGOS — TOKEN (Miniatura no Tabuleiro)

**Tamanho: 256×256px, fundo transparente**
Formato: losango (diamante) com borda colorida — para diferenciar de personagens.

---

### `drone_walker_token.png` — Walker básico, borda cinza
```
diamond shaped tabletop game enemy token, corrupted military scout drone
viewed from above, small hexagonal metallic body, cracked red sensor eye,
sparking and damaged, inside a dark diamond shape with grey border,
transparent background, bold readable at small size,
professional board game enemy token art
```

---

### `drone_runner_token.png` — Runner rápido, borda cinza claro
```
diamond shaped tabletop game enemy token, fast attack drone
viewed from above, sleek elongated body with twin red sensors,
thruster jets visible, inside a dark diamond with light grey border,
transparent background, bold readable at small size,
professional board game enemy token art
```

---

### `infected_walker_token.png` — Infectado básico, borda roxa
```
diamond shaped tabletop game enemy token, nanomachine infected human
viewed from above, hunched silhouette, glowing blue circuit veins,
inside a dark diamond with purple border ring,
transparent background, bold readable at small size,
professional board game enemy token art
```

---

### `infected_heavy_token.png` — Infectado pesado, borda roxa escura
```
diamond shaped tabletop game enemy token, large heavily mutated human
infected by nanomachines viewed from above, massive build,
blue crystalline growths on body, inside a large dark diamond
with dark purple border, larger than walker token,
transparent background, bold readable at small size,
professional board game enemy token art
```

---

### `security_walker_token.png` — Robô de segurança, borda amarela
```
diamond shaped tabletop game enemy token, bipedal security robot
viewed from above, black silver armored chassis, red optical sensor,
inside a dark diamond with yellow border ring,
transparent background, bold readable at small size,
professional board game enemy token art
```

---

### `security_abomination_token.png` — SENTINEL-9 Boss, borda vermelha
```
diamond shaped tabletop game enemy token, massive SENTINEL-9 boss robot
viewed from above, enormous black frame with four weapon arms,
central glowing red eye, clearly bigger than other enemy tokens,
inside a large dark diamond with bright red glowing border,
transparent background, bold readable at small size,
professional board game enemy token art, imposing and threatening
```

---

## ESTRUTURA DE PASTAS

```
assets/sprites/
  tiles/
    tile_lab.png
    tile_corridor.png
    tile_street_ns.png
    tile_street_ew.png
    tile_crossroads.png
    tile_plaza.png
    tile_garage.png
    tile_fuel_depot.png
    tile_server_room.png
    tile_extraction.png
  characters/
    scout_aria_portrait.png
    scout_aria_token.png
    engineer_rex_portrait.png
    engineer_rex_token.png
    medic_nova_portrait.png
    medic_nova_token.png
    soldier_kai_portrait.png
    soldier_kai_token.png
  enemies/
    drone_walker_token.png
    drone_runner_token.png
    infected_walker_token.png
    infected_heavy_token.png
    security_walker_token.png
    security_abomination_token.png
```

---

## NOTAS DE PRODUÇÃO

- **Tiles**: sem fundo transparente, preenchimento total 1024×1024
- **Tokens de personagem**: círculo, fundo transparente, borda colorida por role
- **Tokens de inimigo**: losango/diamante, fundo transparente, borda por tier
- **Escala no board**: tile ocupa ~200×200px na tela, token ~40×40px sobre ele
- Midjourney: use `--ar 1:1 --v 6 --style raw` para tiles realistas
- Para tokens: `--ar 1:1 --v 6` funciona bem
- Para portraits: `--ar 1:1 --v 6 --niji 6` para estilo anime
