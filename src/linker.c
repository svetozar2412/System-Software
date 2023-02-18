#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <elf.h>
#include <string.h>

typedef struct ElfFile
{
  Elf64_Ehdr elfHeader; //        zaglavlje ELF fajla
  uint8_t **sections;
  Elf64_Shdr *sectionHeaderTable; //       zaglavlje o sekcijama
} ElfFile;

typedef struct TempRelaDetails
{
  Elf64_Rela **relaRecords;
  int numberOfRecords;
  int sectionIndexInMainElf;
} TempRelaDetails;

TempRelaDetails *tempRelaDetails = NULL;
int tempRelaDetailsLength = 0;

void printTempRelaDetails()
{
  printf("\nIndex\tSection\tNumber\tRela structs\n");
  for(int r=0;r<tempRelaDetailsLength; r++)
  {
    printf("%d\t%d\t%d\n",r,tempRelaDetails[r].sectionIndexInMainElf,tempRelaDetails[r].numberOfRecords);
    Elf64_Rela* rela_section=(Elf64_Rela*)(*(tempRelaDetails[r].relaRecords));
    for (int s=0;s<tempRelaDetails[r].numberOfRecords;s++)
    {
      printf("[%d,%lx,%lx,%lx]\n", s, rela_section[s].r_offset, rela_section[s].r_info, rela_section[s].r_addend);
    }

    printf("\n");
  }
}

void printRelaDetails(ElfFile elfFile,int rela_section_index)
{
  Elf64_Rela* rela_section=(Elf64_Rela*)(elfFile.sections[rela_section_index]);
  printf("\nIndex\tOffset\tInfo\tAddend\n");
  for (int i = 0; i < elfFile.sectionHeaderTable[rela_section_index].sh_size/sizeof(Elf64_Rela); i++)
  {
    printf("%d.\t%lx\t%lx\t%lx\n", i, rela_section[i].r_offset, rela_section[i].r_info, rela_section[i].r_addend);
  }
}

void printSectionDetails(ElfFile elfFile)
{
  printf("\nIndex\tName\tType\tAddr\tSize\tLink\tInfo\n\n");
  for (int i = 0; i < elfFile.elfHeader.e_shnum; i++)
  {
    printf("%d.\t%s\t%d\t%lx\t%ld\t%d\t%d\n\n", i, &elfFile.sections[elfFile.elfHeader.e_shstrndx][elfFile.sectionHeaderTable[i].sh_name], elfFile.sectionHeaderTable[i].sh_type, elfFile.sectionHeaderTable[i].sh_addr, elfFile.sectionHeaderTable[i].sh_size, elfFile.sectionHeaderTable[i].sh_link, elfFile.sectionHeaderTable[i].sh_info);
    if(elfFile.sectionHeaderTable[i].sh_type!=4)
    {
      for(int j=0;j<elfFile.sectionHeaderTable[i].sh_size;j++)
      {
        printf("%x\t",elfFile.sections[i][j]);
        if(j%8==7)printf("\n");
      }
    }
    else printRelaDetails(elfFile,i);
    printf("\n\n");
  }
}

int getIndexOfSymTab(ElfFile elfFile)
{
  for (int i = 0; i < elfFile.elfHeader.e_shnum; i++)
  {
    if (elfFile.sectionHeaderTable[i].sh_type == SHT_SYMTAB)
    {
      return i;
    }
  }
  return -1;
}

void printSymbolDetails(ElfFile elfFile)
{
  printf("\nIndex\tName\tInfo\tSection\tValue\n");
  Elf64_Sym *sym_tab = (Elf64_Sym *)(elfFile.sections[getIndexOfSymTab(elfFile)]);
  for (int i = 0; i < elfFile.sectionHeaderTable[getIndexOfSymTab(elfFile)].sh_size / sizeof(Elf64_Sym); i++)
  {
    printf("%d.\t%s\t%x\t%d\t%lx\n", i, &elfFile.sections[elfFile.sectionHeaderTable[getIndexOfSymTab(elfFile)].sh_link][sym_tab[i].st_name], sym_tab[i].st_info, sym_tab[i].st_shndx, sym_tab[i].st_value);
  }
}

int getSectionIndex(ElfFile elfFile, char *section_name)
{
  int shstrtab_index = elfFile.elfHeader.e_shstrndx;
  for (int i = 0; i < elfFile.elfHeader.e_shnum; i++)
  {
    if (!strcmp(section_name, &(elfFile.sections[shstrtab_index][elfFile.sectionHeaderTable[i].sh_name])))
    {
      return i;
    }
  }
  return -1;
}

int getSectionSymbolRecordIndex(ElfFile elfFile, int section_index)
{
  int symtab_index = getIndexOfSymTab(elfFile);
  if (symtab_index == -1)
    return -2;

  for (int i = 0; i < elfFile.sectionHeaderTable[symtab_index].sh_size / sizeof(Elf64_Sym); i++)
  {
    if (((Elf64_Sym *)(elfFile.sections[symtab_index]))[i].st_shndx == section_index && ELF32_ST_TYPE(((Elf64_Sym *)(elfFile.sections[symtab_index]))[i].st_info) == STT_SECTION)
    {
      return i;
    }
  }
  return -1;
}

int addNewSection(ElfFile *elfFile, char *section_name, Elf64_Shdr section_header, Elf64_Sym section_as_symbol)
{
  int shstrtab_index = (*elfFile).elfHeader.e_shstrndx;
  int symtab_index = getIndexOfSymTab(*elfFile);
  if (symtab_index == -1)
  {
    printf("Error: Symbol table doesn't exist!\n");
    exit(3);
  }
  ((*elfFile).sections)[shstrtab_index] = (uint8_t *)realloc(((*elfFile).sections)[shstrtab_index], ((*elfFile).sectionHeaderTable)[shstrtab_index].sh_size + strlen(section_name) + 1);
  if(!((*elfFile).sections)[shstrtab_index])
  {
    printf("Error: Memory alocation failed!\n");
    exit(20);
  }
  strcpy(&((*elfFile).sections[shstrtab_index][(*elfFile).sectionHeaderTable[shstrtab_index].sh_size]), section_name);
  section_header.sh_name = elfFile->sectionHeaderTable[shstrtab_index].sh_size;
  section_header.sh_size=0;//ova linija mozda moze da napravi gresku
  (*elfFile).sectionHeaderTable[shstrtab_index].sh_size += strlen(section_name) + 1;
  (*elfFile).sectionHeaderTable = (Elf64_Shdr *)realloc((*elfFile).sectionHeaderTable, ((*elfFile).elfHeader.e_shnum + 1)*sizeof(Elf64_Shdr));
  if(!(*elfFile).sectionHeaderTable)
  {
    printf("Error: Memory alocation failed!\n");
    exit(20);
  }
  (*elfFile).elfHeader.e_shnum += 1;
  
  
  elfFile->sectionHeaderTable[elfFile->elfHeader.e_shnum - 1] = section_header;
  elfFile->sections = (uint8_t **)realloc(elfFile->sections, elfFile->elfHeader.e_shnum * sizeof(uint8_t *));
  (*elfFile).sections[(*elfFile).elfHeader.e_shnum - 1] = NULL;
  (*elfFile).sections[symtab_index] = (uint8_t *)realloc((*elfFile).sections[symtab_index], (*elfFile).sectionHeaderTable[symtab_index].sh_size + sizeof(Elf64_Sym));
  section_as_symbol.st_shndx = (*elfFile).elfHeader.e_shnum - 1;
  *((Elf64_Sym *)(&(*elfFile).sections[symtab_index][(*elfFile).sectionHeaderTable[symtab_index].sh_size])) = section_as_symbol;
  (*elfFile).sectionHeaderTable[symtab_index].sh_size += sizeof(Elf64_Sym);

  return (*elfFile).elfHeader.e_shnum - 1;
}

void addSymbolToSymTab(ElfFile *elfFile, Elf64_Sym symbol, char *symbol_name)
{
  int symtab_index = getIndexOfSymTab(*elfFile);
  int strtab_index = elfFile->sectionHeaderTable[symtab_index].sh_link;

  elfFile->sections[strtab_index] = (uint8_t *)realloc(elfFile->sections[strtab_index], elfFile->sectionHeaderTable[strtab_index].sh_size + strlen(symbol_name) + 1);
  strcpy(&(elfFile->sections[strtab_index][elfFile->sectionHeaderTable[strtab_index].sh_size]), symbol_name);
  symbol.st_name = elfFile->sectionHeaderTable[strtab_index].sh_size;
  elfFile->sectionHeaderTable[strtab_index].sh_size += strlen(symbol_name) + 1;

  elfFile->sections[symtab_index] = (uint8_t *)realloc(elfFile->sections[symtab_index], elfFile->sectionHeaderTable[symtab_index].sh_size + sizeof(Elf64_Sym));
  *((Elf64_Sym *)(&elfFile->sections[symtab_index][elfFile->sectionHeaderTable[symtab_index].sh_size])) = symbol;
  elfFile->sectionHeaderTable[symtab_index].sh_size += sizeof(Elf64_Sym);
}

int getIndexOfSymbol(ElfFile elfFile, char *symbol_name)
{
  int symtab_index = getIndexOfSymTab(elfFile);
  Elf64_Sym *sym_tab = (Elf64_Sym *)(elfFile.sections[symtab_index]);
  int strtab_index = elfFile.sectionHeaderTable[symtab_index].sh_link;
  if (symtab_index == -1)
    return -2;

  for (int i = 0; i < elfFile.sectionHeaderTable[symtab_index].sh_size / sizeof(Elf64_Sym); i++)
  {
    if (!strcmp(symbol_name, &(elfFile.sections[strtab_index][sym_tab[i].st_name])))
    {
      return i;
    }
  }
  return -1;
}

int getIndexOfRelaSection(ElfFile elfFile, int section_index)
{
  int shstrtab_index = elfFile.elfHeader.e_shstrndx;
  for (int i = 0; i < elfFile.elfHeader.e_shnum; i++)
  {
    if (elfFile.sectionHeaderTable[i].sh_type == SHT_RELA && elfFile.sectionHeaderTable[i].sh_info == section_index)
    {
      return i;
    }
  }
  return -1;
}

int addNewRelaSection(ElfFile *elfFile, Elf64_Shdr section_header)
{
  elfFile->sectionHeaderTable = (Elf64_Shdr *)realloc(elfFile->sectionHeaderTable, (elfFile->elfHeader.e_shnum + 1)*sizeof(Elf64_Shdr));
  elfFile->sectionHeaderTable[elfFile->elfHeader.e_shnum]=section_header;
  elfFile->elfHeader.e_shnum += 1;
  elfFile->sections = (uint8_t **)realloc(elfFile->sections, elfFile->elfHeader.e_shnum * sizeof(uint8_t **));
  elfFile->sections[elfFile->elfHeader.e_shnum - 1] = NULL;
  return elfFile->elfHeader.e_shnum - 1;
}

int findUnresolvedSymbols(ElfFile elfFile)
{
  int sym_tab_index = getIndexOfSymTab(elfFile);
  int sym_tab_length = elfFile.sectionHeaderTable[sym_tab_index].sh_size / sizeof(Elf64_Sym);
  Elf64_Sym *sym_tab = (Elf64_Sym *)(elfFile.sections[sym_tab_index]);
  int unresolved_symbols = 0;
  for (int i = 0; i < sym_tab_length; i++)
  {
    if (sym_tab[i].st_shndx == 0 && ELF32_ST_TYPE(sym_tab[i].st_info)== STT_NOTYPE && ELF64_ST_BIND(sym_tab[i].st_info)==STB_GLOBAL )
    {
      char *symbol_name = &(elfFile.sections[elfFile.sectionHeaderTable[sym_tab_index].sh_link][sym_tab[i].st_name]);
      printf("Error: Symbol %s is undefined!\n", symbol_name);
      unresolved_symbols++;
    }
  }
  return unresolved_symbols;
}

void updateOffsetsInRelaSections(ElfFile *elfFile)
{
  for (int i = 0; i < elfFile->elfHeader.e_shnum; i++)
  {
    if (elfFile->sectionHeaderTable[i].sh_type == SHT_RELA)
    {
      Elf64_Rela *rela_section = (Elf64_Rela *)(elfFile->sections[i]);
      int rela_section_length = elfFile->sectionHeaderTable[i].sh_size / sizeof(Elf64_Rela);
      int resolving_section_index = elfFile->sectionHeaderTable[i].sh_info;
      for (int j = 0; j < rela_section_length; j++)
      {
        rela_section[j].r_offset += elfFile->sectionHeaderTable[resolving_section_index].sh_addr;
      }
    }
  }
}

void updateSymbolValuesForExecution(ElfFile* elfFile)
{
  int sym_tab_index = getIndexOfSymTab(*elfFile);
  int sym_tab_length = elfFile->sectionHeaderTable[sym_tab_index].sh_size / sizeof(Elf64_Sym);
  Elf64_Sym *sym_tab = (Elf64_Sym *)(elfFile->sections[sym_tab_index]);
  int pc=0;
  for(int i=0;i<elfFile->elfHeader.e_shnum;i++)
  {
    if(elfFile->sectionHeaderTable[i].sh_type==SHT_PROGBITS || elfFile->sectionHeaderTable[i].sh_type==SHT_NOBITS)
    {
      elfFile->sectionHeaderTable[i].sh_addr=pc;
      pc+=elfFile->sectionHeaderTable[i].sh_size;
    }
  }
  for (int i = 0; i < sym_tab_length; i++)
  {
    if (elfFile->sectionHeaderTable[sym_tab[i].st_shndx].sh_type==SHT_PROGBITS || elfFile->sectionHeaderTable[sym_tab[i].st_shndx].sh_type==SHT_NOBITS)
    {
      sym_tab[i].st_value+=elfFile->sectionHeaderTable[sym_tab[i].st_shndx].sh_addr;
    }
  }
}

void resolveSymbols(ElfFile* elfFile)
{
  for (int i = 0; i < elfFile->elfHeader.e_shnum; i++)
  {
    if (elfFile->sectionHeaderTable[i].sh_type == SHT_RELA)
    {
      Elf64_Rela *rela_section = (Elf64_Rela *)(elfFile->sections[i]);
      int rela_section_length = elfFile->sectionHeaderTable[i].sh_size / sizeof(Elf64_Rela);
      int resolving_section_index = elfFile->sectionHeaderTable[i].sh_info;
      Elf64_Sym* sym_tab=(Elf64_Sym*)(elfFile->sections[getIndexOfSymTab(*elfFile)]);
      uint16_t section_address=elfFile->sectionHeaderTable[resolving_section_index].sh_addr;
      for (int j = 0; j < rela_section_length; j++)
      {
        int symbol_index=ELF64_R_SYM(rela_section[j].r_info); 
        int rel_type=ELF64_R_TYPE(rela_section[j].r_info);
        uint16_t location=rela_section[j].r_offset;
        int16_t addend=rela_section[j].r_addend;
        
        if(rel_type== R_X86_64_16)
        {
          //printf("Symbol_value=%ld, Addend=%d, Location=%d\n",sym_tab[symbol_index].st_value,addend,location);
          *((uint16_t*)(&(elfFile->sections[resolving_section_index][location-section_address])))=addend+sym_tab[symbol_index].st_value;
        }
        else if(rel_type== R_X86_64_PC16)
        {
          //printf("Symbol_value=%ld, Addend=%d, Location=%d\n",sym_tab[symbol_index].st_value,addend,location);
          *((uint16_t*)(&(elfFile->sections[resolving_section_index][location-section_address])))=addend+sym_tab[symbol_index].st_value-location;
        }
        else
        {
          printf("Error: Unsupported relocate type!\n");
          exit(30);
        }
        //rela_section[j].r_offset += elfFile->sectionHeaderTable[resolving_section_index].sh_addr;
      }
    }
  }
}

void writeDataToHexFile(ElfFile elfFile, char *filename)
{
  FILE *hex_file = fopen(filename, "w");
  if (!hex_file)
  {
    printf("Error: Hex file could not be opened!\n");
    exit(11);
  }
  uint16_t pc = 0;
  for (int i = 0; i < elfFile.elfHeader.e_shnum; i++)
  {
    if (elfFile.sectionHeaderTable[i].sh_type == SHT_PROGBITS || elfFile.sectionHeaderTable[i].sh_type == SHT_NOBITS)
    {
      for (int j = 0; j < elfFile.sectionHeaderTable[i].sh_size; j++)
      {
        if (pc % 8 == 0)
        {
          fprintf(hex_file, "%04x:", pc);
        }
        fprintf(hex_file, " %02x", elfFile.sections[i][j]);
        if (pc % 8 == 7)
        {
          fprintf(hex_file, "\n");
        }
        pc++;
      }
    }
  }

  fclose(hex_file);
}

void main(int argc, char *argv[])
{
  if (argc < 5 || strcmp(argv[1], "-hex") || strcmp(argv[2], "-o"))
  {
    printf("Invalid format! Expected format: ./linker -hex -o out_file.hex in_file_1.0 in_file_2.o ...\n");
    exit(1);
  }
  else
  {
    ElfFile mainElf;
    ElfFile localElf;
    ElfFile *tempElf;
    for (int i = 4; i < argc; i++)
    {
      FILE *obj_file = fopen(argv[i], "r");
      if (!obj_file)
      {
        printf("File %s could not be opened!\n", argv[i]);
        exit(2);
      }

      if (i == 4)
        tempElf = &mainElf;
      else
        tempElf = &localElf;
      fread(&(tempElf->elfHeader), sizeof(Elf64_Ehdr), 1, obj_file);
      fseek(obj_file, tempElf->elfHeader.e_shoff, SEEK_SET);
      tempElf->sectionHeaderTable = (Elf64_Shdr *)calloc(tempElf->elfHeader.e_shnum, sizeof(Elf64_Shdr));
      fread(tempElf->sectionHeaderTable, sizeof(Elf64_Shdr), tempElf->elfHeader.e_shnum, obj_file);
      tempElf->sections = (uint8_t **)calloc(tempElf->elfHeader.e_shnum, sizeof(uint8_t *));
      for (int j = 0; j < tempElf->elfHeader.e_shnum; j++)
      {
        fseek(obj_file, tempElf->sectionHeaderTable[j].sh_offset, SEEK_SET);
        if (tempElf->sectionHeaderTable[j].sh_size == 0)
        {
          tempElf->sections[j] = NULL;
        }
        else
        {
          tempElf->sections[j] = (uint8_t *)calloc(tempElf->sectionHeaderTable[j].sh_size, sizeof(uint8_t));
          fread(tempElf->sections[j], 1, tempElf->sectionHeaderTable[j].sh_size, obj_file);
        }
      }

      if (i == 4)
      {
        fclose(obj_file);
        continue;
      }

      for (int j = 0; j < localElf.elfHeader.e_shnum; j++)
      {
        char *section_name = &(localElf.sections[localElf.elfHeader.e_shstrndx][localElf.sectionHeaderTable[j].sh_name]);
        if (localElf.sectionHeaderTable[j].sh_type == SHT_PROGBITS || localElf.sectionHeaderTable[j].sh_type == SHT_NOBITS)
        {
          int section_index = getSectionIndex(mainElf, section_name);
          if (section_index == -1)
          {
            if (localElf.sectionHeaderTable[j].sh_size > 0)
            {
              int section_symbol_index = getSectionSymbolRecordIndex(localElf, j);
              if (section_symbol_index < 0)
              {
                printf("Error: Section symbol doesn't exist!\n");
                exit(4);
              }
              Elf64_Sym section_symbol = *((Elf64_Sym *)(&localElf.sections[getIndexOfSymTab(localElf)][section_symbol_index * sizeof(Elf64_Sym)]));
              section_index=addNewSection(&mainElf,section_name,localElf.sectionHeaderTable[j],section_symbol);

              mainElf.sections[section_index] = (uint8_t *)calloc(localElf.sectionHeaderTable[j].sh_size, 1);

              memcpy(&(mainElf.sections[section_index][mainElf.sectionHeaderTable[section_index].sh_size]), localElf.sections[j], localElf.sectionHeaderTable[j].sh_size);
            }
            else
              continue;
          }
          else
          {
            mainElf.sections[section_index] = (uint8_t *)realloc(mainElf.sections[section_index], mainElf.sectionHeaderTable[section_index].sh_size + localElf.sectionHeaderTable[j].sh_size);
            memcpy(&(mainElf.sections[section_index][mainElf.sectionHeaderTable[section_index].sh_size]), localElf.sections[j], localElf.sectionHeaderTable[j].sh_size);
          }

          // copy symbols that belong to this sectiion into global symbol table,change their values if they're defined,and copy their names to string table
          Elf64_Sym *local_sym_tab = (Elf64_Sym *)(localElf.sections[getIndexOfSymTab(localElf)]);
          for (int z = 0; z < localElf.sectionHeaderTable[getIndexOfSymTab(localElf)].sh_size / sizeof(Elf64_Sym); z++)
          {
            if (local_sym_tab[z].st_shndx == j && ELF64_ST_TYPE(local_sym_tab[z].st_info) != STT_SECTION)
            {
              int shouldAddSymbol = 0;
              for (int y = 0; y < mainElf.sectionHeaderTable[getIndexOfSymTab(mainElf)].sh_size / sizeof(Elf64_Sym); y++)
              {
                Elf64_Sym *main_sym_tab = (Elf64_Sym *)(mainElf.sections[getIndexOfSymTab(mainElf)]);
                // IF THE NAME IS SAME,BUT NEITHER IS FROM SECTION UNDEFINED
                
                if (!strcmp(&localElf.sections[localElf.sectionHeaderTable[getIndexOfSymTab(localElf)].sh_link][local_sym_tab[z].st_name], &mainElf.sections[mainElf.sectionHeaderTable[getIndexOfSymTab(mainElf)].sh_link][main_sym_tab[y].st_name]))
                {
                  if (ELF64_ST_BIND(local_sym_tab[z].st_info) == STB_GLOBAL && ELF64_ST_BIND(main_sym_tab[y].st_info) == STB_GLOBAL)
                  {
                    if (local_sym_tab[z].st_shndx != 0 && main_sym_tab[y].st_shndx != 0)
                    {
                      printf("Error: Multiple definitions of symbol %s!\n",&localElf.sections[localElf.sectionHeaderTable[getIndexOfSymTab(localElf)].sh_link][local_sym_tab[z].st_name]);
                      exit(8);
                    }
                    else if (local_sym_tab[z].st_shndx == 0 && main_sym_tab[y].st_shndx != 0)
                    {
                      // U LOKALNOM ELFU JE SIMBOL UND,A U MAIN-U POSTOJI KAO GLOBAL => ZA SADA PRESKOCI
                      break;
                    }
                    else if (local_sym_tab[z].st_shndx != 0 && main_sym_tab[y].st_shndx == 0)
                    {
                      int index_in_mainelf = getSectionIndex(mainElf,&localElf.sections[localElf.elfHeader.e_shstrndx][localElf.sectionHeaderTable[local_sym_tab[z].st_shndx].sh_name]);
                      main_sym_tab[y].st_shndx = index_in_mainelf;
                      main_sym_tab[y].st_value = mainElf.sectionHeaderTable[index_in_mainelf].sh_size + local_sym_tab[z].st_value;
                      break;
                    }
                  }
                }
                if (y == mainElf.sectionHeaderTable[getIndexOfSymTab(mainElf)].sh_size / sizeof(Elf64_Sym) - 1)
                {
                  shouldAddSymbol = 1;
                  break;
                }
              }
              if (shouldAddSymbol)
              {
                Elf64_Sym symbol = local_sym_tab[z];
                symbol.st_shndx = getSectionIndex(mainElf,&localElf.sections[localElf.elfHeader.e_shstrndx][localElf.sectionHeaderTable[local_sym_tab[z].st_shndx].sh_name]);
                symbol.st_value = mainElf.sectionHeaderTable[symbol.st_shndx].sh_size + local_sym_tab[z].st_value;
                addSymbolToSymTab(&mainElf, symbol, &localElf.sections[localElf.sectionHeaderTable[getIndexOfSymTab(localElf)].sh_link][local_sym_tab[z].st_name]);
              }
            }
          }

          int local_rela_section_index = getIndexOfRelaSection(localElf, j);
          int main_rela_section_index = getIndexOfRelaSection(mainElf, section_index);

          if (local_rela_section_index > 0)
          {
            Elf64_Rela *local_rela_section = (Elf64_Rela *)localElf.sections[local_rela_section_index];
            for (int z = 0; z < localElf.sectionHeaderTable[local_rela_section_index].sh_size / sizeof(Elf64_Rela); z++)
            {
              local_rela_section[z].r_offset += mainElf.sectionHeaderTable[section_index].sh_size;
              int local_symbol_index = ELF64_R_SYM(local_rela_section[z].r_info);
              Elf64_Sym symbol = ((Elf64_Sym *)(localElf.sections[getIndexOfSymTab(localElf)]))[local_symbol_index];

              //AKO JE U RELA ULAZU SIMBOL ZAPRAVO SEKCIJA,POTREBNO JE AZURIRATI ADDEND ZA VELICINU TE SEKCIJE U MAIN ELF-U,AKO JE SEKCIJA VEC DODATA U MAIN ELF,U SUPROTNOM ADDEND NE TREBA MENJATI
              if (ELF32_ST_TYPE(symbol.st_info) == STT_SECTION)
              {
                char* symbol_name = &(localElf.sections[localElf.elfHeader.e_shstrndx][localElf.sectionHeaderTable[symbol.st_shndx].sh_name]);
                int section_index = getSectionIndex(mainElf, symbol_name);
                if(section_index < 0) continue;
                local_rela_section[z].r_addend += mainElf.sectionHeaderTable[section_index].sh_size;
              }
            }
            if (!tempRelaDetails)
            {
              tempRelaDetails = (TempRelaDetails *)calloc(1, sizeof(TempRelaDetails));
              tempRelaDetailsLength = 1;
            }
            else
            {
              tempRelaDetails = (TempRelaDetails *)realloc(tempRelaDetails, (1 + tempRelaDetailsLength) * sizeof(TempRelaDetails));
              tempRelaDetailsLength += 1;
            }
            tempRelaDetails[tempRelaDetailsLength - 1].sectionIndexInMainElf = section_index;
            tempRelaDetails[tempRelaDetailsLength - 1].numberOfRecords = localElf.sectionHeaderTable[local_rela_section_index].sh_size / sizeof(Elf64_Rela);
            tempRelaDetails[tempRelaDetailsLength - 1].relaRecords = (Elf64_Rela **)(&(localElf.sections[local_rela_section_index]));
          }

          mainElf.sectionHeaderTable[section_index].sh_size += localElf.sectionHeaderTable[j].sh_size;
        }
      }

      for (int z = 0; z < tempRelaDetailsLength; z++)
      {
        for (int w = 0; w < tempRelaDetails[z].numberOfRecords; w++)
        {
          Elf64_Rela* rela_section=(Elf64_Rela*)(*(tempRelaDetails[z].relaRecords));
          int local_symbol_index = ELF64_R_SYM(rela_section[w].r_info);
          char *symbol_name;
          Elf64_Sym symbol = ((Elf64_Sym *)(localElf.sections[getIndexOfSymTab(localElf)]))[local_symbol_index];
          if (ELF32_ST_TYPE(symbol.st_info) == STT_SECTION)
          {
            symbol_name = &(localElf.sections[localElf.elfHeader.e_shstrndx][localElf.sectionHeaderTable[symbol.st_shndx].sh_name]);
          }
          else if (ELF32_ST_TYPE(symbol.st_info) == STT_NOTYPE)
          {
            symbol_name = &(localElf.sections[localElf.sectionHeaderTable[getIndexOfSymTab(localElf)].sh_link][symbol.st_name]);
          }

          //ZAMENJEN JE LOCAL ELF SA MAIN ELFOM U LINIJI ISPOD
          Elf64_Sym* sym_tab = (Elf64_Sym *)(mainElf.sections[getIndexOfSymTab(mainElf)]);
          for (int y = 0; y < mainElf.sectionHeaderTable[getIndexOfSymTab(mainElf)].sh_size / sizeof(Elf64_Sym); y++)
          {
            Elf64_Sym symbol_from_main = ((Elf64_Sym *)(mainElf.sections[getIndexOfSymTab(mainElf)]))[y];
            if (ELF32_ST_TYPE(sym_tab[y].st_info) == STT_SECTION || ELF32_ST_BIND(sym_tab[y].st_info) == STB_GLOBAL)
            {
              char* symbol_name_from_main_elf;
              if (ELF32_ST_TYPE(symbol.st_info) == STT_SECTION)
              {
                symbol_name_from_main_elf = &(mainElf.sections[mainElf.elfHeader.e_shstrndx][mainElf.sectionHeaderTable[symbol_from_main.st_shndx].sh_name]);
              }
              else if (ELF32_ST_BIND(symbol.st_info) == STB_GLOBAL)
              {
                symbol_name_from_main_elf = &(mainElf.sections[mainElf.sectionHeaderTable[getIndexOfSymTab(mainElf)].sh_link][symbol_from_main.st_name]);
              }
              //char* symbol_name_from_main_elf = &(mainElf.sections[mainElf.sectionHeaderTable[getIndexOfSymTab(mainElf)].sh_link][sym_tab[y].st_name]);
              if (!strcmp(symbol_name, symbol_name_from_main_elf))
              {
                (*(tempRelaDetails[z].relaRecords))[w].r_info = ELF64_R_INFO(ELF64_R_SYM(y), ELF64_R_TYPE((*(tempRelaDetails[z].relaRecords))[w].r_info));
                break;
              }
            }
          }
        }

        // ADD/APPEND THIS RELA TABLE IN MAIN ELF
        int main_rela_section_index = getIndexOfRelaSection(mainElf, tempRelaDetails[z].sectionIndexInMainElf);
        if (main_rela_section_index < 0)
        {
          Elf64_Shdr rela_header = {
              .sh_name = 0,
              .sh_type = SHT_RELA,
              .sh_flags = SHF_INFO_LINK,
              .sh_addr = 0x0000000000000000l,
              .sh_offset = 0,
              .sh_size = 0,
              .sh_link = getIndexOfSymTab(mainElf),
              .sh_info = tempRelaDetails[z].sectionIndexInMainElf,
              .sh_addralign = 8,
              .sh_entsize = sizeof(Elf64_Rela),
          };
          main_rela_section_index = addNewRelaSection(&mainElf, rela_header);
        }

        // ALOCIRAJ/REALOCIRAJ PROSTOR ZA REKORDE IZ RELA TABELE,I PREKOPIRAJ IH
        if (mainElf.sections[main_rela_section_index] == NULL)
        {
          mainElf.sections[main_rela_section_index] = (uint8_t *)calloc(tempRelaDetails[z].numberOfRecords, sizeof(Elf64_Rela));
        }
        else
        {
          mainElf.sections[main_rela_section_index] = (uint8_t *)realloc(mainElf.sections[main_rela_section_index],mainElf.sectionHeaderTable[main_rela_section_index].sh_size + tempRelaDetails[z].numberOfRecords * sizeof(Elf64_Rela));
        }

        Elf64_Rela *main_rela_section = (Elf64_Rela *)(mainElf.sections[main_rela_section_index]);
        int current_rela_section_length = mainElf.sectionHeaderTable[main_rela_section_index].sh_size / sizeof(Elf64_Rela);

        for (int w = 0; w < tempRelaDetails[z].numberOfRecords; w++)
        {
          main_rela_section[current_rela_section_length + w] = (*(tempRelaDetails[z].relaRecords))[w];
        }

        mainElf.sectionHeaderTable[main_rela_section_index].sh_size += tempRelaDetails[z].numberOfRecords * sizeof(Elf64_Rela);
      }

      // DEALOCIRAJ STRUKTURE PODATAKA,SEM MAIN_ELF-A
      free(tempRelaDetails);
      tempRelaDetails = NULL;
      tempRelaDetailsLength = 0;
      for (int j = 0; j < localElf.elfHeader.e_shnum; j++)
      {
        if (localElf.sections[j] != NULL)
        {
          free(localElf.sections[j]);
        }
      }
      free(localElf.sectionHeaderTable);
      localElf.sectionHeaderTable=NULL;
      free(localElf.sections);
      localElf.sections=NULL;

      fclose(obj_file);
    }

    // PROVERI DA LI JE NEKI SIMBOL OSTAO NERAZRESEN
    int num_of_unresolved_syms = findUnresolvedSymbols(mainElf);
    if (num_of_unresolved_syms > 0)
    {
      exit(10);
    }
    //AZURIRAJ VREDNOSTI SIMBOLA
    updateSymbolValuesForExecution(&mainElf);

    // AZURIRAJ OFFSETE U RELA TABELAMA
    updateOffsetsInRelaSections(&mainElf);

    resolveSymbols(&mainElf);
    
    // UPISI PODATKE U HEX FAJL
    writeDataToHexFile(mainElf, argv[3]);

    // DEALOCIRAJ MAIN_ELF
    for (int j = 0; j < mainElf.elfHeader.e_shnum; j++)
    {
      if (mainElf.sections[j] != NULL)
      {
        free(mainElf.sections[j]);
      }
    }
    free(mainElf.sectionHeaderTable);
    free(mainElf.sections);
  }
}