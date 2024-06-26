(lang dune 3.0)

(using menhir 2.1)
(using dune_site 0.1)
(using mdx 0.2)
(using directory-targets 0.1)

(cram enable)

(generate_opam_files true)

(name owi)

(license AGPL-3.0-or-later)

(authors
 "Léo Andrès <contact@ndrs.fr>"
 "Pierre Chambart <pierre.chambart@ocamlpro.com>"
 "Filipe Marques <filipe.s.marques@tecnico.ulisboa.pt>"
 "Eric Patrizio <epatrizio@mpns.fr>"
 "Arthur Carcano <arthur.carcano@ocamlpro.com")

(maintainers "Léo Andrès <contact@ndrs.fr>")

(source
 (github ocamlpro/owi))

(package
 (name owi)
 (synopsis
  "OCaml toolchain to work with WebAssembly, including an interpreter")
 (description
  "owi is an OCaml toolchain to work with WebAssembly. It provides an interpreter as an executable and a library.")
 (tags
  (owi ocaml webassembly wasm interpreter compiler))
 (depends
  (ocaml
   (>= 5.1))
  (integers
   (>= 0.5.1))
  cmdliner
  conf-clang
  sedlex
  (menhir
   (and
    :build
    (>= 20220210)))
  ocaml_intrinsics
  uutf
  (bisect_ppx
   (and
    :with-test
    (>= 2.5)
    :dev))
  (ocb
   (and
    :with-test
    (>= 0.1)
    :dev))
  (odoc :with-doc)
  (crunch :dev)
  bos
  (smtml (>= 0.1.1))
  (mdx
   (and
    :with-test
    (>= 2.1)))
  (crowbar :with-test)
  (graphics :dev)
  (tiny_httpd :dev)
  (ocamlformat :dev)
  (rusage :dev)
  (tyxml :dev)
  digestif
  xmlm
  (hc (>= 0.3))
  (processor (>= 0.1))
  dune-site)
 (sites (share binc) (share libc)))
