# Eternal Night — Plano do projeto

> "O sol não nasce há mil anos." Desde que o Rei dos Demônios tomou o trono,
> quatro reinos jazem sob o seu jugo. **Treine · Liberte · Devolva o Dia.**

## O combinado

- A versão 3 (Three.js num único `index.html` dentro de um APK) chegou no limite.
- Refazer o jogo em **Godot 4** buscando visual e sensação mais próximos de AAA.
- **Tudo feito em código** pelo Claude Code: o dono do projeto não precisa abrir o
  editor do Godot (só em último caso).
- O APK é gerado automaticamente pelo GitHub Actions a cada push e publicado na
  página **Releases** do repositório, para baixar direto no celular.
- O código da versão antiga está em `referencia/eternal_night_v3_threejs.html`
  (imagens removidas) para consultar ao portar cada sistema.

## Como funciona

| Coisa | Onde |
|---|---|
| Entrada do jogo | `scenes/main.tscn` → `scripts/main.gd` |
| Mundo (céu, terreno, ruínas, fogo, árvores, castelo) | `scripts/world.gd` |
| Cavaleiro (movimento, combate, câmera, modelo) | `scripts/player.gd` |
| Interface e controles de toque | `scripts/hud.gd` |
| Shader do terreno | `shaders/terrain.gdshader` |
| Gerar APK | `.github/workflows/build-apk.yml` |

Testar sem abrir o editor (gera uma captura de tela):

```
godot --path . -- --shot=saida.png --yaw=0.5 --pos=0,8 --attack
```

## Etapas

- [x] **1. Base** — projeto Godot 4.6 (renderizador Mobile), terreno procedural com
  colisão, céu da noite eterna, névoa, brilho, lua, braseiros com fogo e fagulhas,
  ruínas, árvores mortas, rochas, castelo do Rei dos Demônios ao norte, cinzas
  caindo. Cavaleiro em 3ª pessoa: andar, correr, pular, esquiva com
  invencibilidade, combo de 3 golpes com rastro na espada, estamina. Controles de
  teclado/mouse, controle (gamepad) e toque (joystick + botões, multitoque).
  APK automático pelo GitHub Actions.
- [ ] **2. Combate de verdade** — inimigos (demônios) com IA, vida, dano, stagger,
  parry, trava de alvo, sons de golpe, morte e respawn.
- [ ] **3. Mundo vivo** — os 4 reinos/biomas, vilas, NPCs, diálogos e missões
  (portar da v3: `npcTalk`, `dialogue`, `qStart`...).
- [ ] **4. Cavalo** — montar, andaduras, estábulo.
- [ ] **5. Progressão** — XP, habilidades, treino, duelos, totens e libertação dos reinos.
- [ ] **6. Chefes** — Senhor do Inverno, ... , Rei dos Demônios. Final: o sol nasce.
- [ ] **7. Água e pesca**, save com slots, menu de opções gráficas.
- [ ] **8. Multiplayer online** (a v3 usava PeerJS).
- [ ] **9. Visual AAA** — trocar primitivas por modelos 3D e animações reais
  (ex.: assets CC0 do Kenney/Quaternius ou modelos próprios), áudio e música.
