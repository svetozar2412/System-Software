# file: section_symbol.s (ne radi u emulatoru,zbog beskonacne petlje,samo je kreiran za testiranje linkera)
.section rrrr
.word pppp

.section pppp
# prekidna rutina za reset
.global isr_reset
isr_reset:
  jmp pppp

.end
