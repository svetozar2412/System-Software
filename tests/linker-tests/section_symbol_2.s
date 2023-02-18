# file: section_symbol_2.s (ne radi u emulatoru,zbog beskonacne petlje,samo je kreiran za testiranje linkera)
.section rrrr
.word pppp

.section pppp
# prekidna rutina za reset
.global isr_reset_2
isr_reset_2:
  jmp pppp

.end
