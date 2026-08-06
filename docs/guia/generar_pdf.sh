#!/usr/bin/env bash
# Genera docs/Guia-Fuga.pdf a partir de docs/guia/guia.html.
#
# Uso:  ./docs/guia/generar_pdf.sh
#
# Necesita un Chromium o Google Chrome instalado. Si el tuyo está en otra ruta,
# pásalo por la variable CHROME:
#   CHROME=/usr/bin/google-chrome ./docs/guia/generar_pdf.sh

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENTRADA="$RAIZ/docs/guia/guia.html"
SALIDA="$RAIZ/docs/Guia-Fuga.pdf"

if [[ -z "${CHROME:-}" ]]; then
	for candidato in \
		/opt/pw-browsers/chromium \
		"$(command -v chromium || true)" \
		"$(command -v chromium-browser || true)" \
		"$(command -v google-chrome || true)"
	do
		if [[ -n "$candidato" && -x "$candidato" ]]; then
			CHROME="$candidato"
			break
		fi
	done
fi

if [[ -z "${CHROME:-}" ]]; then
	echo "No se encontró Chromium ni Chrome. Instálalo o define la variable CHROME." >&2
	exit 1
fi

"$CHROME" \
	--headless \
	--disable-gpu \
	--no-sandbox \
	--run-all-compositor-stages-before-draw \
	--virtual-time-budget=10000 \
	--no-pdf-header-footer \
	--print-to-pdf="$SALIDA" \
	"file://$ENTRADA" 2>&1 | grep -v -E "^\[|DevTools|Fontconfig" || true

if [[ ! -s "$SALIDA" ]]; then
	echo "No se generó el PDF." >&2
	exit 1
fi

echo "Guía generada: $SALIDA ($(du -h "$SALIDA" | cut -f1))"
