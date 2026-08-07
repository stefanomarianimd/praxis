#!/bin/sh
# Rigenera index.md dal README del repository privato.
#
# La pagina pubblica è un ESTRATTO: si toglie il titolo H1 (lo mette il tema) e
# si riscrivono i riferimenti a percorsi interni, che su una pagina pubblica non
# vogliono dire nulla. Tutto il resto è identico, così le due copie non divergono.
SORGENTE="${1:-$HOME/Desktop/GestionaleAmbulatorio/README.md}"
{
  printf -- '---\ntitle: Praxis\n---\n\n'
  tail -n +3 "$SORGENTE" \
    | sed 's#^Full results, including what the model catches and what it does not:$#Full results, including what the model catches and what it does not, are kept#' \
    | sed 's#^`architecture/riferimenti/misure_astensione.md`\.$#with the code and available on request.#'
} > index.md
echo "index.md rigenerato da $SORGENTE"
