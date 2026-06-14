# Maintainer: Ruzbyte

pkgname=luminotes
pkgver=1.0.0
pkgrel=1
pkgdesc="Infinite canvas note-taking application"
arch=('x86_64')
url="https://github.com/ruzbyte/luminotes"
license=('custom')
depends=('gtk3')
makedepends=('clang' 'cmake' 'flutter' 'ninja')
options=('!strip')

build() {
  cd "$startdir"
  flutter pub get
  flutter build linux --release
}

package() {
  cd "$startdir"

  install -d "$pkgdir/opt/luminotes"
  cp -a build/linux/x64/release/bundle/data "$pkgdir/opt/luminotes/"
  cp -a build/linux/x64/release/bundle/lib "$pkgdir/opt/luminotes/"
  install -Dm755 build/linux/x64/release/bundle/luminotes \
    "$pkgdir/opt/luminotes/luminotes"

  install -d "$pkgdir/usr/bin"
  ln -s /opt/luminotes/luminotes "$pkgdir/usr/bin/luminotes"

  install -Dm644 linux/com.ruzbyte.luminotes.desktop \
    "$pkgdir/usr/share/applications/com.ruzbyte.luminotes.desktop"
  install -Dm644 assets/logo.png \
    "$pkgdir/usr/share/icons/hicolor/512x512/apps/com.ruzbyte.luminotes.png"
}
