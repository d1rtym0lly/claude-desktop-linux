# Claude Desktop для Arch Linux, CachyOS и NixOS

Сборка **официального** приложения Claude Desktop (Chat, Cowork и Claude Code в одном окне) для дистрибутивов, которые Anthropic пока официально не поддерживает.

Anthropic выпускает Linux-версию (бета) только как `.deb` для Ubuntu и Debian. Этот репозиторий берёт этот `.deb` прямо с серверов Anthropic и превращает его в нативный пакет:

| Дистрибутив | Как устанавливается | Обновления |
|---|---|---|
| Arch Linux | `PKGBUILD` → пакет pacman | `git pull && makepkg -si` |
| CachyOS, EndeavourOS, Manjaro и другие на базе Arch | тот же `PKGBUILD` | так же |
| NixOS (и Nix на любом Linux) | flake: пакет, overlay, NixOS-модуль | `nix flake update` |

Архитектуры: `x86_64` и `aarch64`.

> **Неофициально.** Проект не связан с Anthropic. Приложение Claude Desktop закрытое, и здесь его **нет**: в репозитории только скрипты сборки, а само приложение скачивается с `downloads.claude.ai` во время сборки, и его контрольная сумма проверяется. Так же устроены пакеты в AUR.

---

## Установка

### Arch Linux и CachyOS

```bash
git clone https://github.com/d1rtym0lly/claude-desktop-linux.git
cd claude-desktop-linux/arch
makepkg -si
```

`makepkg` скачает официальный `.deb`, сверит SHA-256 из индекса apt-репозитория Anthropic, соберёт пакет `claude-desktop` и установит его через pacman. Удаление: `sudo pacman -R claude-desktop`.

Если раньше ты собирал пакет вручную (через `debtap` или свой PKGBUILD с тем же именем `claude-desktop`), он просто заменится.

**Обновление:**

```bash
cd claude-desktop-linux && git pull && cd arch && makepkg -si
```

Новую версию в репозитории каждый день проверяет GitHub Actions (см. «Как это работает»), поэтому `git pull` сразу приносит свежую версию и её контрольные суммы.

### NixOS (flake)

`flake.nix` системы:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    claude-desktop.url = "github:d1rtym0lly/claude-desktop-linux";
    claude-desktop.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, claude-desktop, ... }: {
    nixosConfigurations.my-laptop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        claude-desktop.nixosModules.default
        {
          programs.claude-desktop.enable = true;
          # Для Cowork пользователь должен быть в группе kvm:
          users.users.gleb.extraGroups = [ "kvm" ];
        }
      ];
    };
  };
}
```

Модуль `programs.claude-desktop` делает следующее:

- ставит приложение;
- при `cowork.enable = true` (по умолчанию) ставит QEMU и `virtiofsd` и загружает модуль ядра `vhost_vsock`;
- включает `gnome-keyring`, чтобы вход сохранялся (`mkDefault`, можно переопределить);
- включает `nix-ld`: Claude Code внутри приложения запускает готовые Linux-бинарники, а на NixOS они без `nix-ld` не стартуют.

Другие варианты:

```bash
# запустить без установки
nix run github:d1rtym0lly/claude-desktop-linux
# поставить в профиль (Nix на любом дистрибутиве)
nix profile install github:d1rtym0lly/claude-desktop-linux
```

Ещё есть `overlays.default`, который добавляет `pkgs.claude-desktop`. Через overlay пакет собирается из твоего `nixpkgs`, поэтому там нужно разрешить несвободный пакет: `nixpkgs.config.allowUnfreePredicate = p: lib.getName p == "claude-desktop";`.

---

## Что оптимизировано

Официальный `.deb` рассчитан на Ubuntu с GNOME. На других системах есть типичные проблемы, и сборка их исправляет:

| Проблема | Что делает сборка |
|---|---|
| **На Hyprland, Sway, niri, i3 и подобных при каждом запуске приходится заново входить в аккаунт.** Electron находит хранилище паролей только в GNOME и KDE, в остальных средах сессия не сохраняется. | Лаунчер определяет рабочий стол и, если это не GNOME или KDE, передаёт `--password-store=gnome-libsecret`. Вход сохраняется в `gnome-keyring` (или в любом другом Secret Service, например KeePassXC). |
| В Wayland-сессии приложение может работать через XWayland: размыто при масштабировании и медленнее. | В Wayland приложение запускается нативно: `--ozone-platform-hint=auto`, декорации окон, IME. Отключается через `CLAUDE_NO_WAYLAND=1`. |
| Каждый раз нужно ждать холодного старта. | `claude-desktop-autostart on` запускает приложение при входе в систему. После этого открытие из меню только поднимает уже запущенное окно, и это происходит мгновенно. |
| Своих флагов Chromium/Electron не передать. | Файл `~/.config/claude-desktop-flags.conf`, по одному флагу на строку (как у `code-flags.conf` в Arch). |
| `.deb` прописывает apt-репозиторий и ключ, а на Arch и NixOS они не нужны. | Удаляются: `/etc/apt`, `/etc/default`, `/usr/share/keyrings`. |
| На NixOS бинарники ищут библиотеки в `/usr/lib`. | `autoPatchelfHook` прописывает пути к библиотекам из Nix store, а библиотеки, загружаемые через `dlopen` (libGL, Vulkan, libsecret, libnotify, PulseAudio, udev), добавляются через `LD_LIBRARY_PATH`. |

Само приложение не изменяется: файлы Anthropic остаются как есть, меняется только способ их запуска.

### Настройки лаунчера

```bash
# автозапуск при входе в систему
claude-desktop-autostart on      # off / status

# свои флаги
cat > ~/.config/claude-desktop-flags.conf <<'EOF'
# по одному флагу на строку, # — комментарий
--disable-gpu
EOF
```

| Переменная | Что делает |
|---|---|
| `CLAUDE_PASSWORD_STORE=kwallet6` | принудительно задать хранилище паролей (`gnome-libsecret`, `kwallet5`, `kwallet6`, `basic`) |
| `CLAUDE_NO_WAYLAND=1` | запускать через XWayland (если на NVIDIA или с Wayland есть артефакты) |
| `CLAUDE_LAUNCHER_DEBUG=1` | вывести в терминал итоговую команду запуска |

---

## Cowork (виртуальная машина)

Cowork запускает задачи в виртуальной машине QEMU/KVM. На Arch и CachyOS:

```bash
sudo pacman -S --needed qemu-base edk2-ovmf virtiofsd
sudo usermod -aG kvm $USER
echo vhost_vsock | sudo tee /etc/modules-load.d/vhost_vsock.conf
sudo modprobe vhost_vsock
```

После этого выйди из системы и зайди снова. На NixOS всё это, кроме группы `kvm`, делает модуль. Аппаратная виртуализация (VT-x или AMD-V) должна быть включена в BIOS/UEFI.

> Cowork на Arch проверен меньше всего. Приложение рассчитано на пути Debian (`/usr/share/OVMF/…`, `/usr/libexec/virtiofsd`), а в Arch они другие. Если Cowork пишет, что не нашёл QEMU или прошивку, см. «Решение проблем».

---

## Как это работает

```
downloads.claude.ai (официальный apt-репозиторий Anthropic)
 ├─ dists/stable/main/binary-*/Packages   ← версия и SHA-256
 └─ pool/main/c/claude-desktop/*.deb      ← само приложение
        │
        ├─ scripts/update.sh  (каждый день в GitHub Actions)
        │     читает индекс → обновляет arch/PKGBUILD и sources.json → коммит
        │
        ├─ arch/PKGBUILD   (makepkg на твоём компьютере)
        │     скачивает .deb → проверяет SHA-256 → распаковывает data.tar
        │     → убирает apt-файлы → ставит лаунчер перед /usr/bin/claude-desktop
        │     → направляет .desktop-файлы через лаунчер → пакет pacman
        │
        └─ nix/package.nix   (nix build)
              fetchurl по sources.json → dpkg-deb → autoPatchelf
              → тот же лаунчер + обёртка с LD_LIBRARY_PATH/GSettings
```

**Лаунчер** (`common/claude-desktop-launcher.sh`) — это небольшой bash-скрипт, который устанавливается как `/usr/bin/claude-desktop`. Официальную точку входа из `.deb` он не заменяет, а запускает её (`exec`) с подобранными флагами. Поэтому, если Anthropic что-то поменяет внутри приложения, сборка продолжит работать.

**CI** (`.github/workflows/build.yml`) на каждый push и при выходе новой версии:

1. собирает пакет в контейнере `archlinux:base-devel` и устанавливает его;
2. проверяет через `ldd`, что все библиотеки находятся (если нет, в `depends` чего-то не хватает);
3. запускает приложение в Xvfb на 30 секунд (smoke-тест);
4. собирает Nix-пакет (`autoPatchelf` упадёт, если какой-то библиотеки нет) и проверяет flake.

Готовые бинарные пакеты CI **не публикует**: это означало бы распространять закрытое приложение.

### Структура

```
arch/PKGBUILD                     сборка для Arch / CachyOS
common/claude-desktop-launcher.sh лаунчер (общий для Arch и Nix)
common/claude-desktop-autostart.sh  включение и выключение автозапуска
nix/package.nix                   Nix-деривация
nix/module.nix                    NixOS-модуль programs.claude-desktop
flake.nix                         flake: packages, overlay, nixosModules
sources.json                      версия, URL и SHA-256 для Nix
scripts/update.sh                 обновление версии из индекса Anthropic
.github/workflows/build.yml       автообновление и проверочные сборки
```

### Что использовалось

- официальный Claude Desktop `.deb` и apt-индекс Anthropic: https://code.claude.com/docs/en/desktop-linux
- `makepkg`/`pacman`, `bsdtar` (libarchive) для распаковки `.deb`
- Nix: `stdenv.mkDerivation`, `dpkg`, `autoPatchelfHook`, `wrapGAppsHook3`, `makeWrapper`
- GitHub Actions: `archlinux:base-devel`, `cachix/install-nix-action`, Xvfb
- флаги Electron/Chromium: `--password-store`, `--ozone-platform-hint`, `--enable-features=WaylandWindowDecorations`, `--enable-wayland-ime`

---

## Решение проблем

**Вход не сохраняется.** Поставь хранилище паролей: `sudo pacman -S gnome-keyring` (вне KDE) или `kwallet` (KDE). В оконных менеджерах без своей сессии (Hyprland, Sway, i3) хранилище нужно запускать самостоятельно, например `exec-once = gnome-keyring-daemon --start --components=secrets` для Hyprland. Проверить, что получает приложение: `CLAUDE_LAUNCHER_DEBUG=1 claude-desktop`.

**Чёрное окно или артефакты (часто на NVIDIA).** Попробуй `CLAUDE_NO_WAYLAND=1 claude-desktop` или добавь `--disable-gpu` в `~/.config/claude-desktop-flags.conf`.

**Cowork не находит QEMU или прошивку UEFI (Arch).** Посмотри, какой путь указан в сообщении, и создай ссылку на файл Arch. Например, для прошивки:
```bash
sudo mkdir -p /usr/share/OVMF
sudo ln -s /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE_4M.fd
```
и для `virtiofsd`:
```bash
sudo mkdir -p /usr/libexec && sudo ln -s /usr/lib/virtiofsd /usr/libexec/virtiofsd
```
Если поможет, создай issue, и это добавят в пакет.

**`makepkg`: «The .deb has no /usr/bin/claude-desktop».** Anthropic поменяла структуру пакета. Создай issue.

**Claude Code внутри приложения не запускается на NixOS.** Нужен `programs.nix-ld.enable = true;` (модуль включает его по умолчанию).

---

## Что проверено, а что нет

- Логика PKGBUILD и Nix-деривации проверена на тестовых `.deb` с тремя вариантами устройства точки входа (абсолютная ссылка, относительная ссылка, скрипт). NixOS-модуль проверен на nixos-unstable, пакет вычисляется на nixos-25.11 и unstable.
- Сборки из настоящего `.deb` выполняет CI, их результат виден во вкладке Actions.
- На реальном железе проверена только ручная установка того же `.deb` на Arch. Cowork на Arch и NixOS и запуск на aarch64 пока не проверялись.

## Лицензия

Скрипты в репозитории распространяются под лицензией MIT (см. `LICENSE`). Claude Desktop — собственность Anthropic, его использование регулируется условиями Anthropic.
