# Sourced pelos scripts de tool/: define `verovio_bridge`, a pasta do
# verovio_flutter_bridge. Padrão: vizinha deste repositório
# (../verovio_flutter_bridge, pode ser um symlink) — o mesmo caminho
# relativo que o pubspec.yaml usa. VEROVIO_BRIDGE sobrescreve.
verovio_bridge="${VEROVIO_BRIDGE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/verovio_flutter_bridge}"
