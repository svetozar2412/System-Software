%{
#include <stdio.h>     /* C declarations used in actions */
#include <stdlib.h>
#include <ctype.h>
#include <elf.h>
#include <string.h>

void yyerror (char *s);
void skipBytes(int size);
int symbolEntry(char* symbol_name);
void addWordLiteral(int num);
void processJumpInstruction(uint8_t firstByte);
void processMemoryInstruction(uint8_t firstByte,char* rd);
void addLabelToList(char* label_name);
void removeLabelsFromList();
void addGlobalSymbols(char* symbols);
void addExternSymbols(char* symbols);
int addNewSection(char* section_name);
int stringSectionDataEntry();
void finishAssembling();
int getOffset(char *needle, char *haystack, int haystackLen);
void generateBasicSections();
int yylex();
int yydebug = 1;

#define SHSTRTAB   \
    "\0.shstrtab"    \
    "\0.strtab"  \
	"\0.symtab"    \
    "\0.text" \
    "\0.data"      \
    "\0.bss"       \
    "\0"

#define SHSTRTAB_LENGTH 44

enum
{
    SECTION_NDX_UNDEF = 0,
    SECTION_NDX_SHSTRTAB,
    SECTION_NDX_STRTAB,
    SECTION_NDX_SYMTAB,
    SECTION_NDX_TEXT,
    SECTION_NDX_DATA,
    SECTION_NDX_BSS,
};

enum
{
    SYMTAB_NDX_UNDEF = 0,
    SYMTAB_NDX_TEXT,
    SYMTAB_NDX_DATA,
    SYMTAB_NDX_BSS,
};

typedef enum
{
    HALT = 0,
    INTERRUPT,
    IRET,
    CALL,
    RET,
    JMP,
    JEQ,
    JNE,
    JGT,
    PUSH,
    POP,
    XCHG,
    ADD,
    SUB,
    MUL,
    DIVIDE,
    CMP,
    NOT,
    AND,
    OR,
    XOR,
    TEST,
    SHL,
    SHR,
    LDR,
    STR,
} Instruction;

typedef enum {
    IMMEDIATE=0,
    REG_DIRECT,
    REG_INDIRECT,
    REG_INDIRECT_WITH_ADD,
    MEMORY,
    REG_DIRECT_WITH_ADD,
    PC_RELATIVE,
} AddressingType;

typedef enum {
    NO_UPDATE=0,
    MINUS_2_PREFIX,
    PLUS_2_PREFIX,
    MINUS_2_POSTFIX,
    PLUS_2_POSTFIX,
} UpdateRegType;

typedef enum {
    LITERAL=0,
    SYMBOL,
} ImmediateType;

typedef enum {
    GLOBAL_UNDEFINED=14,
    EXTERN_UNUSED,
} CustomBindings;

typedef struct CustomSections {
	uint8_t* data;
	uint8_t sectionIndex;
} CustomSection;

typedef struct RelaSections {
	Elf64_Rela* data;
	uint8_t sectionIndex;
} RelaSection;

struct ElfFile
    {
        Elf64_Ehdr elfHeader;                    //       zaglavlje ELF fajla
		CustomSection *customSections;
        int customSectionsLength;
        Elf64_Sym* symtab;                     // tabela simbola
        RelaSection* relaSections;                  // relokaciona tabela
        int relaSectionsLength;
        Elf64_Shdr* sectionHeaderTable;        //       zaglavlje o sekcijama
    } elfFile = {
			.elfHeader = {
            .e_ident = {/* Magic number and other info */
                        /* [0] EI_MAG        */ 0x7F, 'E', 'L', 'F',
                        /* [4] EI_CLASS      */ ELFCLASS64,
                        /* [5] EI_DATA       */ ELFDATA2LSB,
                        /* [6] EI_VERSION    */ EV_CURRENT,
                        /* [7] EI_OSABI      */ ELFOSABI_SYSV,
                        /* [8] EI_ABIVERSION */ 0,
                        /* [9-15] EI_PAD     */ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
                      },
            .e_type = ET_REL,                                                  
            .e_machine = EM_X86_64,                                            
            .e_version = EV_CURRENT,                                           
            .e_entry = 0,                                                      
            .e_phoff = 0,                                                      
            .e_shoff = 0, /* Potrebno je izmeniti pocetnu adresu zaglavlja za sekcije */
            .e_flags = 0,
            .e_ehsize = sizeof(Elf64_Ehdr),
            .e_phentsize = 0,
            .e_phnum = 0,
            .e_shentsize = sizeof(Elf64_Shdr),
            .e_shnum = 0,                                                      /* Potrebno je izmeniti ukupan broj sekcija*/
            .e_shstrndx = 0                                 /* Potrebno je izmeniti indeks tabele koja cuva nazive sekcija */
      },
	  .customSections=NULL,
      .customSectionsLength=0,
      .symtab=NULL,                     // tabela simbola
      .relaSections=NULL,                  // relokaciona tabela
      .relaSectionsLength=0,
      .sectionHeaderTable=NULL,
	};

typedef struct PatchSymbol
{
    char* symbol_name;
    struct SectionAndAddress
    {
        int section_entry;
        uint16_t address;
        AddressingType addr_type;
    } *locations;
    int number_of_locations;
} PatchSymbol;

typedef struct RegisterNumberIdentifier
{
    char* regist;
    int num;
    char* ident;
    AddressingType addrType;
    UpdateRegType updateType;
    ImmediateType immediateType;
} RegisterNumberIdentifier;

//int position_in_current_section = 0;
int current_section_index = 0;
int current_section_size = 0;
int current_section_data_index = 0;
PatchSymbol* patchTable=NULL;
int patchTableSize=0;

RegisterNumberIdentifier rni = {NULL,0,NULL,IMMEDIATE,NO_UPDATE,LITERAL};
char** label_list=NULL;

int label_list_length=0;


extern FILE* yyin;
char* out_file;
void putInstruction(Instruction i,char* rd,char* rs);
void addWordSymbol(char* symbol_name,AddressingType addr_type);
void addSymbolToPatchTable(char* symbol_name,int address,AddressingType addr_type);

%}

%union {int num; char* id; char* registerr;};         /* Yacc definitions */
%start line
%token colon
%token comma
%token plus
%token minus
%token asterisk
%token left_square_bracket
%token right_square_bracket
%token percent
%token dollar
%token new_line
%token string
%token global
%token external
%token section
%token word
%token skip
%token ascii
%token equ
%token end
%token halt
%token interrupt
%token iret
%token call
%token ret
%token jmp
%token jeq
%token jne
%token jgt
%token push
%token pop
%token xchg
%token add
%token sub
%token mul
%token divide
%token cmp
%token not
%token and
%token or
%token xor
%token test
%token shl
%token shr
%token ldr
%token str
%token <registerr> reg
%token <num> number
%token <id> identifier
%type <id> line label instruction directive statement identifiers list member operand1 operand2

%%

/* descriptions of expected inputs     corresponding actions (in C) */

line    : label colon new_line						{;}
		| label colon {removeLabelsFromList();} instruction new_line		    {;}
		| label colon directive	new_line			{;}
		| {removeLabelsFromList();} instruction new_line						{;}
		| directive	new_line						{;}
        | new_line                                  {;}
      ;

line    : line label colon new_line					{;}
		| line label colon {removeLabelsFromList();} instruction new_line		{;}
		| line label colon directive new_line		{;}
		| line {removeLabelsFromList();} instruction new_line					{;}
		| line directive new_line					{;}
        | line new_line					            {;}
			;

label : identifier  {addLabelToList($1);}
			;

instruction : halt                  {putInstruction(HALT,NULL,NULL);}
       	| interrupt reg             {putInstruction(INTERRUPT,$2,NULL);}
       	| iret                      {putInstruction(IRET,NULL,NULL);}
		| call operand2             {putInstruction(CALL,NULL,$2);}
       	| ret                       {putInstruction(RET,NULL,NULL);}
		| jmp operand2              {putInstruction(JMP,NULL,$2);}
       	| jeq operand2              {putInstruction(JEQ,NULL,$2);}
		| jne operand2              {putInstruction(JNE,NULL,$2);}
       	| jgt operand2              {putInstruction(JGT,NULL,$2);}
		| push reg                  {putInstruction(PUSH,$2,NULL);}
       	| pop reg                   {putInstruction(POP,$2,NULL);}
		| xchg reg comma reg        {putInstruction(XCHG,$2,$4);}
       	| add reg comma reg         {putInstruction(ADD,$2,$4);}
		| sub reg comma reg         {putInstruction(SUB,$2,$4);}
       	| mul reg comma reg         {putInstruction(MUL,$2,$4);}
		| divide reg comma reg      {putInstruction(DIVIDE,$2,$4);}
       	| cmp reg comma reg         {putInstruction(CMP,$2,$4);}
		| not reg                   {putInstruction(NOT,$2,NULL);}
       	| and reg comma reg         {putInstruction(AND,$2,$4);}
       	| or reg comma reg          {putInstruction(OR,$2,$4);}
		| xor reg comma reg         {putInstruction(XOR,$2,$4);}
       	| test reg comma reg        {putInstruction(TEST,$2,$4);}
		| shl reg comma reg         {putInstruction(SHL,$2,$4);}
       	| shr reg comma reg         {putInstruction(SHR,$2,$4);}
		| ldr reg comma operand1    {putInstruction(LDR,$2,NULL);}
       	| str reg comma operand1    {putInstruction(STR,$2,NULL);}
       	;

directive : global identifiers                  {addGlobalSymbols($2);}
		| external identifiers			        {addExternSymbols($2);}
		| section identifier			        {current_section_index = addNewSection($2);}
		| word {removeLabelsFromList();} list			                    {}
		| skip {removeLabelsFromList();} number			                {skipBytes($3);}
		| ascii string			                {;}
		| equ identifier comma statement		{;}
		| end			                        {finishAssembling();}
        ;

statement : member						{;}
		| member plus statement			{;}
		| member minus statement		{;}
				;

identifiers : identifier						{;}
		| identifier comma identifiers			{;}
				;

list : member						{;}
		| member comma list			{;}
				;

member : identifier				            {addWordSymbol($1,IMMEDIATE);}
		| number							{addWordLiteral($1);}
				;

operand1 : dollar number				{RegisterNumberIdentifier x={NULL,$2,NULL,IMMEDIATE,NO_UPDATE,LITERAL};rni=x;}
		| dollar identifier					{RegisterNumberIdentifier x={NULL,0,$2,IMMEDIATE,NO_UPDATE,SYMBOL};rni=x;}
		| number										{RegisterNumberIdentifier x={NULL,$1,NULL,MEMORY,NO_UPDATE,LITERAL};rni=x;}
		| identifier								{RegisterNumberIdentifier x={NULL,0,$1,MEMORY,NO_UPDATE,SYMBOL};rni=x;}
		| percent identifier				{RegisterNumberIdentifier x={NULL,0,$2,PC_RELATIVE,NO_UPDATE,SYMBOL};rni=x;}
		| reg												{RegisterNumberIdentifier x={$1,0,NULL,REG_DIRECT,NO_UPDATE,LITERAL};rni=x;}
		| left_square_bracket reg right_square_bracket													{RegisterNumberIdentifier x={$2,0,NULL,REG_INDIRECT,NO_UPDATE,LITERAL};rni=x;}
		| left_square_bracket reg plus number right_square_bracket							{RegisterNumberIdentifier x={$2,$4,NULL,REG_INDIRECT_WITH_ADD,NO_UPDATE,LITERAL};rni=x;}
		| left_square_bracket reg plus identifier right_square_bracket					{RegisterNumberIdentifier x={$2,0,$4,REG_INDIRECT_WITH_ADD,NO_UPDATE,SYMBOL};x.ident[strlen(x.ident)-1]='\0';rni=x;}
				;

operand2 : number				{RegisterNumberIdentifier x={NULL,$1,NULL,IMMEDIATE,NO_UPDATE,LITERAL};rni=x;}
		| identifier					{RegisterNumberIdentifier x={NULL,0,$1,IMMEDIATE,NO_UPDATE,SYMBOL};rni=x;}
		| percent identifier										{RegisterNumberIdentifier x={NULL,0,$2,PC_RELATIVE,NO_UPDATE,SYMBOL};rni=x;}
		| asterisk number								{RegisterNumberIdentifier x={NULL,$2,NULL,MEMORY,NO_UPDATE,LITERAL};rni=x;}
		| asterisk identifier				{RegisterNumberIdentifier x={NULL,0,$2,MEMORY,NO_UPDATE,SYMBOL};rni=x;}
		| asterisk reg												{RegisterNumberIdentifier x={$2,0,NULL,REG_DIRECT,NO_UPDATE,LITERAL};rni=x;}
		| asterisk left_square_bracket reg right_square_bracket													{RegisterNumberIdentifier x={$3,0,NULL,REG_INDIRECT,NO_UPDATE,LITERAL};rni=x;}
		| asterisk left_square_bracket reg plus number right_square_bracket							{RegisterNumberIdentifier x={$3,$5,NULL,REG_INDIRECT_WITH_ADD,NO_UPDATE,LITERAL};rni=x;}
		| asterisk left_square_bracket reg plus identifier right_square_bracket					{RegisterNumberIdentifier x={$3,0,$5,REG_INDIRECT_WITH_ADD,NO_UPDATE,SYMBOL};x.ident[strlen(x.ident)-1]='\0';rni=x;}
				;



%%                     /* C code */

int getRelaSectionIndex(int section_index)
{
    int rela_section_index = -1;
    for(int i=0;i<elfFile.elfHeader.e_shnum;i++)
    {
        if(elfFile.sectionHeaderTable[i].sh_type==SHT_RELA && elfFile.sectionHeaderTable[i].sh_info==section_index)
        {
            rela_section_index = i;
            break;
        }
    }
    return rela_section_index;
}

int createRelaSection(int section_index)
{
    elfFile.sectionHeaderTable = (Elf64_Shdr*)realloc(elfFile.sectionHeaderTable,(elfFile.elfHeader.e_shnum+1)*sizeof(Elf64_Shdr));
    int shstrtab_entry;
    char section_name[200];
    strcpy(section_name,".rela");
    strcat(section_name,&(elfFile.customSections[0].data[elfFile.sectionHeaderTable[section_index].sh_name]));
    //AKO POSTOJI STRING U TABELI NAZIVA SEKCIJA,ISKORISTI TAJ ENTRY
    if(!(shstrtab_entry=getOffset(section_name, elfFile.customSections[0].data, elfFile.sectionHeaderTable[SECTION_NDX_SHSTRTAB].sh_size)))
    {
        elfFile.customSections[0].data = (char*)realloc(elfFile.customSections[0].data,(elfFile.sectionHeaderTable[SECTION_NDX_SHSTRTAB].sh_size+strlen(section_name)+1)*sizeof(char));
        shstrtab_entry=elfFile.sectionHeaderTable[SECTION_NDX_SHSTRTAB].sh_size;
        memcpy(&(elfFile.customSections[0].data[shstrtab_entry]),section_name,strlen(section_name)+1);
        elfFile.sectionHeaderTable[SECTION_NDX_SHSTRTAB].sh_size+=strlen(section_name)+1;
    }
    //STRUKTURA NOVE TABELE RELOKACIJA
    Elf64_Shdr x = {
                .sh_name = shstrtab_entry,
                .sh_type = SHT_RELA,
                .sh_flags = SHF_INFO_LINK,
                .sh_addr = 0x0000000000000000l,
                .sh_offset = 0,
                .sh_size = 0,
                .sh_link = SECTION_NDX_SYMTAB,
                .sh_info = section_index,
                .sh_addralign = 8,
                .sh_entsize = sizeof(Elf64_Rela),
            };
    int rela_section_index = elfFile.elfHeader.e_shnum;
    elfFile.sectionHeaderTable[elfFile.elfHeader.e_shnum++] = x;
    return rela_section_index;
}

int getRelaSectionDataEntry(int rela_section_index)
{
    int rela_section_data_entry=-1;
    for(int i=0;i<elfFile.relaSectionsLength;i++)
    {
        if(elfFile.relaSections[i].sectionIndex==rela_section_index)
        {
            rela_section_data_entry=i;
            break;
        }
    }
    return rela_section_data_entry;
}

void setRecordInRelaSection(Elf64_Rela record,int section_index)
{
    int rela_section_data_entry = -1;

    //PROBAJ DA NADJES TABELU RELOKACIJA ZA TRENUTNU SEKCIJU
    int rela_section_index=getRelaSectionIndex(section_index);
    
    //AKO NIJE JOS UVEK DODATA TABELA RELOKACIJA ZA OVU SEKCIJU
    if(rela_section_index==-1)
    {
        rela_section_index = createRelaSection(section_index);

        //ALOCIRAJ PROSTOR ZA RELA PODATKE
        if(elfFile.relaSectionsLength)elfFile.relaSections=(RelaSection*)realloc(elfFile.relaSections,(elfFile.relaSectionsLength+1)*sizeof(RelaSection));
        else elfFile.relaSections=(RelaSection*)calloc(1,sizeof(RelaSection));
        rela_section_data_entry=elfFile.relaSectionsLength;
        elfFile.relaSections[elfFile.relaSectionsLength].sectionIndex=rela_section_index;
        elfFile.relaSectionsLength++;
    }
    else
    {
        rela_section_data_entry=getRelaSectionDataEntry(rela_section_index);
    }

    if(elfFile.relaSections[rela_section_data_entry].data==NULL)
    {
        elfFile.relaSections[rela_section_data_entry].data=(Elf64_Rela*)calloc(1,sizeof(Elf64_Rela));
    }
    else
    {
        elfFile.relaSections[rela_section_data_entry].data=(Elf64_Rela*)realloc(elfFile.relaSections[rela_section_data_entry].data,elfFile.sectionHeaderTable[rela_section_index].sh_size+sizeof(Elf64_Rela));
    }

    //UPISI RELA ZAPIS U RELA TABELU
    elfFile.relaSections[rela_section_data_entry].data[elfFile.sectionHeaderTable[rela_section_index].sh_size/sizeof(Elf64_Rela)]=record;
    elfFile.sectionHeaderTable[rela_section_index].sh_size+=sizeof(Elf64_Rela);
}

void addLabelToList(char* label_name)
{
    if(label_list==NULL)
    {
        label_list=(char**)calloc(1,sizeof(char*));
    }
    else
    {
        label_list=(char**)realloc(label_list,(label_list_length+1)*sizeof(char*));
    }
    label_list[label_list_length]=(char*)calloc(strlen(label_name)+1,sizeof(char));
    //printf("Add label to list:%s\n",label_name);
    strcpy(label_list[label_list_length],label_name);
    label_list_length++;
}

void removeLabelsFromList()
{
    if(!label_list_length) return;
    int i=stringSectionDataEntry();
    int string_table_size=elfFile.sectionHeaderTable[SECTION_NDX_STRTAB].sh_size;
    if(!string_table_size) {elfFile.customSections[i].data=(char*)calloc(1,sizeof(char));elfFile.customSections[i].data[0]='\0';string_table_size++;}
    int sym_tab_size=elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size/sizeof(Elf64_Sym);
            
    for(int j=0;j<label_list_length;j++)
    {
        int skip_iteration=0;
        for(int z=0;z<sym_tab_size;z++)
        {
            int different=strcmp(&(elfFile.customSections[i].data[elfFile.symtab[z].st_name]),label_list[j]);
            if(!different)
            {
                if(ELF64_ST_BIND((elfFile.symtab[z].st_info)==STB_LOCAL) || (ELF64_ST_BIND(elfFile.symtab[z].st_info)==STB_GLOBAL && elfFile.symtab[z].st_shndx!=SYMTAB_NDX_UNDEF))
                {
                    printf("Symbol already exists!\n");
                    exit(2);  //SIMBOL VEC POSTOJI U OVOM FAJLU
                }
                else if(ELF64_ST_BIND(elfFile.symtab[z].st_info)==GLOBAL_UNDEFINED)
                {
                    elfFile.symtab[z].st_info&=0x0F;
                    elfFile.symtab[z].st_info|=STB_GLOBAL<<4;
                    elfFile.symtab[z].st_shndx=current_section_index;
                    elfFile.symtab[z].st_value=0x0000000000000000l | current_section_size;
                    skip_iteration=1;
                    break;
                }
                else if(ELF64_ST_BIND(elfFile.symtab[z].st_info)==EXTERN_UNUSED);
                {
                    //PREGAZI GA,JER CE IME BITI ZAMASKIRANO LABELOM
                    elfFile.symtab[z].st_info&=0x0F;
                    elfFile.symtab[z].st_info|=STB_LOCAL<<4;
                    elfFile.symtab[z].st_shndx=current_section_index;
                    elfFile.symtab[z].st_value=0x0000000000000000l | current_section_size;
                    skip_iteration=1;
                    break;
                }
            }
        }

        if(skip_iteration)
        {
            continue;
        }

        int strtab_entry;
        char* data = elfFile.customSections[i].data;
        if(!(strtab_entry=getOffset(label_list[j], data, string_table_size)))
        {
            data = (char*)realloc(data,(string_table_size+strlen(label_list[j])+1)*sizeof(char));
            strtab_entry=string_table_size;
            memcpy(&(data[strtab_entry]),label_list[j],strlen(label_list[j])+1);
            string_table_size+=strlen(label_list[j])+1;
            
            int symtab_new_size = elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size+sizeof(Elf64_Sym);
            elfFile.symtab = (Elf64_Sym*)realloc(elfFile.symtab,symtab_new_size);
            Elf64_Sym y = {
                        .st_name = strtab_entry,
                        .st_info = ELF64_ST_INFO(STB_LOCAL, STT_NOTYPE),
                        .st_other = STV_DEFAULT,
                        .st_shndx = current_section_index,
                        .st_value = 0x0000000000000000l | current_section_size,
                        .st_size = 0,
                    };
            elfFile.symtab[elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size/sizeof(Elf64_Sym)] = y;
            elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size=symtab_new_size;
        }
        free(label_list[j]);
    }
    free(label_list);
    label_list=NULL;
    label_list_length=0;

    elfFile.sectionHeaderTable[SECTION_NDX_STRTAB].sh_size = string_table_size;
}

void expandSectionAndPushInstruction(void* instruction_value,int size)
{
    elfFile.customSections[current_section_data_index].data=(uint8_t*)realloc(elfFile.customSections[current_section_data_index].data,current_section_size+size);
    for(int i=0;i<size;i++)
    {
        elfFile.customSections[current_section_data_index].data[current_section_size+i]=*((uint8_t*)instruction_value+i);
    }
    current_section_size+=size;
}

void putInstruction(Instruction i,char* rd,char* rs)
{
    switch(i)
    {
        case HALT:
        {
            const int size = 1;
            uint8_t instr[1] = {0x00};
            expandSectionAndPushInstruction(&instr,size);
            
        };break;
        case INTERRUPT:
        {
            const int size = 2;
            uint8_t reg_index = atoi(&(rd[1]));
            uint8_t instr[2] = {0x10, 0x0F | (reg_index<<4)};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case IRET:
        {
            const int size = 1;
            uint8_t instr[1] = {0x20};
            expandSectionAndPushInstruction(&instr,size);
        }break;
        case CALL:
        {
            processJumpInstruction(0x30);
        };break;
        case RET:
        {
            const int size = 1;
            uint16_t instr[1] = {0x40};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case JMP:
        {
            processJumpInstruction(0x50);
        };break;
        case JEQ:
        {
            processJumpInstruction(0x51);
        };break;
        case JNE:
        {
            processJumpInstruction(0x52);
        };break;
        case JGT:
        {
            processJumpInstruction(0x53);
        };break;
        case PUSH:
        {
            const int size = 3;
            uint8_t instr[3]={0xB0,0x06,0x12};
            uint8_t* temp=&(instr[1]);
            *temp|=atoi(&(rd[1]))<<4;
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case POP:
        {
            const int size = 3;
            uint8_t instr[3]={0xA0,0x06,0x42};
            uint8_t* temp=&(instr[1]);
            *temp|=(atoi(&(rd[1])))<<4;
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case XCHG:
        {
            const int size = 2;
            int dest_reg_index = atoi(&(rd[1]));
            int src_reg_index = atoi(&(rs[1]));
            uint8_t instr[2] = {0x60, 0x00 | (dest_reg_index<<4) | src_reg_index};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case ADD:
        {
            const int size = 2;
            int dest_reg_index = atoi(&(rd[1]));
            int src_reg_index = atoi(&(rs[1]));
            uint8_t instr[2] = {0x70, 0x00 | (dest_reg_index<<4) | src_reg_index};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case SUB:
        {
            const int size = 2;
            int dest_reg_index = atoi(&(rd[1]));
            int src_reg_index = atoi(&(rs[1]));
            uint8_t instr[2] = {0x71, 0x00 | (dest_reg_index<<4) | src_reg_index};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case MUL:
        {
            const int size = 2;
            int dest_reg_index = atoi(&(rd[1]));
            int src_reg_index = atoi(&(rs[1]));
            uint8_t instr[2] = {0x72, 0x00 | (dest_reg_index<<4) | src_reg_index};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case DIVIDE:
        {
            const int size = 2;
            int dest_reg_index = atoi(&(rd[1]));
            int src_reg_index = atoi(&(rs[1]));
            uint8_t instr[2] = {0x73, 0x00 | (dest_reg_index<<4) | src_reg_index};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case CMP:
        {
            const int size = 2;
            int dest_reg_index = atoi(&(rd[1]));
            int src_reg_index = atoi(&(rs[1]));
            uint8_t instr[2] = {0x74, 0x00 | (dest_reg_index<<4) | src_reg_index};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case NOT:
        {
            const int size = 2;
            int dest_reg_index = atoi(&(rd[1]));
            uint8_t instr[2] = {0x80, 0x00 | (dest_reg_index<<4)};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case AND:
        {
            const int size = 2;
            int dest_reg_index = atoi(&(rd[1]));
            int src_reg_index = atoi(&(rs[1]));
            uint8_t instr[2] = {0x81, 0x00 | (dest_reg_index<<4) | src_reg_index};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case OR:
        {
            const int size = 2;
            int dest_reg_index = atoi(&(rd[1]));
            int src_reg_index = atoi(&(rs[1]));
            uint8_t instr[2] = {0x82, 0x00 | (dest_reg_index<<4) | src_reg_index};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case XOR:
        {
            const int size = 2;
            int dest_reg_index = atoi(&(rd[1]));
            int src_reg_index = atoi(&(rs[1]));
            uint8_t instr[2] = {0x83, 0x00 | (dest_reg_index<<4) | src_reg_index};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case TEST:
        {
            const int size = 2;
            int dest_reg_index = atoi(&(rd[1]));
            int src_reg_index = atoi(&(rs[1]));
            uint8_t instr[2] = {0x84, 0x00 | (dest_reg_index<<4) | src_reg_index};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case SHL:
        {
            const int size = 2;
            int dest_reg_index = atoi(&(rd[1]));
            int src_reg_index = atoi(&(rs[1]));
            uint8_t instr[2] = {0x90, 0x00 | (dest_reg_index<<4) | src_reg_index};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case SHR:
        {
            const int size = 2;
            int dest_reg_index = atoi(&(rd[1]));
            int src_reg_index = atoi(&(rs[1]));
            uint8_t instr[2] = {0x91, 0x00 | (dest_reg_index<<4) | src_reg_index};
            expandSectionAndPushInstruction(&instr,size);
        };break;
        case LDR:
        {
            processMemoryInstruction(0xA0,rd);
        };break;
        case STR:
        {
            processMemoryInstruction(0xB0,rd);
        };break;
    }
}

void processJumpInstruction(uint8_t firstByte)
{
    if(rni.addrType==IMMEDIATE && rni.immediateType==LITERAL)
    {
        const int size = 5;
        uint8_t instr[5]={firstByte,0xF0,0x00,0x00,0x00};
        uint16_t* temp=(uint16_t*)(&(instr[3]));
        *temp=rni.num;
        expandSectionAndPushInstruction(&instr,size);
    }
    else if(rni.addrType==IMMEDIATE && rni.immediateType==SYMBOL)
    {
        const int size = 3;
        uint8_t instr[3]={firstByte,0xF0,0x00};
        expandSectionAndPushInstruction(&instr,size);
        addWordSymbol(rni.ident,IMMEDIATE);
    }
    else if(rni.addrType==PC_RELATIVE && rni.immediateType==SYMBOL)
    {
        const int size = 3;
        //PC je source registar
        uint8_t instr[3]={firstByte,0XF7,0x05};
        expandSectionAndPushInstruction(&instr,size);
        addWordSymbol(rni.ident,PC_RELATIVE);
    }
    else if(rni.addrType==MEMORY && rni.immediateType==LITERAL)
    {
        const int size = 5;
        uint8_t instr[5]={firstByte,0xF0,0x04,0x00,0x00};
        uint16_t* temp=(uint16_t*)(&(instr[3]));
        *temp=rni.num;
        expandSectionAndPushInstruction(&instr,size);
    }
    else if(rni.addrType==MEMORY && rni.immediateType==SYMBOL)
    {
        const int size = 3;
        uint8_t instr[3]={firstByte,0xF0,0x04};
        expandSectionAndPushInstruction(&instr,size);
        addWordSymbol(rni.ident,IMMEDIATE);
    }
    else if(rni.addrType==REG_DIRECT)
    {
        const int size = 3;
        uint8_t instr[3]={firstByte,0xF0,0x01};
        uint8_t* temp=&(instr[1]);
        *temp|=atoi(&(rni.regist[1]));
        expandSectionAndPushInstruction(&instr,size);
    }
    else if(rni.addrType==REG_INDIRECT)
    {
        const int size = 3;
        uint8_t instr[3]={firstByte,0xF0,0x02};
        uint8_t* temp=&(instr[1]);
        *temp|=atoi(&(rni.regist[1]));
        expandSectionAndPushInstruction(&instr,size);
    }
    else if(rni.addrType==REG_INDIRECT_WITH_ADD && rni.immediateType==LITERAL)
    {
        const int size = 5;
        uint8_t instr[5]={firstByte,0xF0,0x03,0x00,0x00};
        uint8_t* temp=&(instr[1]);
        *temp|=atoi(&(rni.regist[1]));
        uint16_t* temp2=(uint16_t*)(&(instr[3]));
        *temp2=rni.num;
        expandSectionAndPushInstruction(&instr,size);
    }
    else if(rni.addrType==REG_INDIRECT_WITH_ADD && rni.immediateType==SYMBOL)
    {
        const int size = 3;
        uint8_t instr[3]={firstByte,0xF0,0x03};
        uint8_t* temp=&(instr[1]);
        *temp|=atoi(&(rni.regist[1]));
        expandSectionAndPushInstruction(&instr,size);
        addWordSymbol(rni.ident,IMMEDIATE);
    }
}

void processMemoryInstruction(uint8_t firstByte,char* rd)
{
    uint8_t registersByte = atoi(&(rd[1]))<<4;
    if(rni.addrType==IMMEDIATE && rni.immediateType==LITERAL)
    {
        const int size = 5;
        uint8_t instr[5]={firstByte,registersByte,0x00,0x00,0x00};
        uint16_t* temp=(uint16_t*)(&(instr[3]));
        *temp=rni.num;
        expandSectionAndPushInstruction(&instr,size);
    }
    else if(rni.addrType==IMMEDIATE && rni.immediateType==SYMBOL)
    {
        const int size = 3;
        uint8_t instr[3]={firstByte,registersByte,0x00};
        expandSectionAndPushInstruction(&instr,size);
        addWordSymbol(rni.ident,IMMEDIATE);
    }
    else if(rni.addrType==PC_RELATIVE && rni.immediateType==SYMBOL)
    {
        const int size = 3;
        registersByte|=7; //PC je source registar
        uint8_t instr[3]={firstByte,registersByte,0x05};
        expandSectionAndPushInstruction(&instr,size);
        addWordSymbol(rni.ident,PC_RELATIVE);
    }
    else if(rni.addrType==MEMORY && rni.immediateType==LITERAL)
    {
        const int size = 5;
        uint8_t instr[5]={firstByte,registersByte,0x04,0x00,0x00};
        uint16_t* temp=(uint16_t*)(&(instr[3]));
        *temp=rni.num;
        expandSectionAndPushInstruction(&instr,size);
    }
    else if(rni.addrType==MEMORY && rni.immediateType==SYMBOL)
    {
        const int size = 3;
        uint8_t instr[3]={firstByte,registersByte,0x04};
        expandSectionAndPushInstruction(&instr,size);
        addWordSymbol(rni.ident,IMMEDIATE);
    }
    else if(rni.addrType==REG_DIRECT)
    {
        const int size = 3;
        uint8_t instr[3]={firstByte,registersByte,0x01};
        uint8_t* temp=&(instr[1]);
        *temp|=atoi(&(rni.regist[1]));
        expandSectionAndPushInstruction(&instr,size);
    }
    else if(rni.addrType==REG_INDIRECT)
    {
        const int size = 3;
        uint8_t instr[3]={firstByte,registersByte,0x02};
        uint8_t* temp=&(instr[1]);
        *temp|=atoi(&(rni.regist[1]));
        expandSectionAndPushInstruction(&instr,size);
    }
    else if(rni.addrType==REG_INDIRECT_WITH_ADD && rni.immediateType==LITERAL)
    {
        const int size = 5;
        uint8_t instr[5]={firstByte,registersByte,0x03,0x00,0x00};
        uint8_t* temp=&(instr[1]);
        *temp|=atoi(&(rni.regist[1]));
        uint16_t* temp2=(uint16_t*)(&(instr[3]));
        *temp2=rni.num;
        expandSectionAndPushInstruction(&instr,size);
    }
    else if(rni.addrType==REG_INDIRECT_WITH_ADD && rni.immediateType==SYMBOL)
    {
        const int size = 3;
        uint8_t instr[3]={firstByte,registersByte,0x03};
        uint8_t* temp=&(instr[1]);
        *temp|=atoi(&(rni.regist[1]));
        expandSectionAndPushInstruction(&instr,size);
        addWordSymbol(rni.ident,IMMEDIATE);
    }
}

int getCustomSectionDataEntry(int section_index) {
    int entry=-1;
    for(int i=0;i<elfFile.customSectionsLength;i++)
    {
        if(elfFile.customSections[i].sectionIndex==section_index)
        {
            entry=i;
            break;
        }
    }
    return entry;
}

int stringSectionDataEntry() {
    int i;
    for(i=0;i<elfFile.customSectionsLength;i++)
    {
        if(elfFile.customSections[i].sectionIndex==SECTION_NDX_STRTAB)
        {
            break;
        }
        else
        {
            if(i==elfFile.customSectionsLength-1)
            {
                ++(elfFile.customSectionsLength);
                elfFile.customSections=(CustomSection*)realloc(elfFile.customSections,(elfFile.customSectionsLength)*sizeof(CustomSection));
	            elfFile.customSections[elfFile.customSectionsLength-1].sectionIndex=SECTION_NDX_STRTAB;
            }
        }
    }
    return i;
}

void skipBytes(int size)
{
    elfFile.customSections[current_section_data_index].data=(uint8_t*)realloc(elfFile.customSections[current_section_data_index].data,current_section_size+size);
    for(int i=0;i<size;i++)
    {
        elfFile.customSections[current_section_data_index].data[current_section_size+i]=0;
    }
    current_section_size+=size;
}

void addWordLiteral(int num)
{
    const int word_size = 2;
    elfFile.customSections[current_section_data_index].data=(uint8_t*)realloc(elfFile.customSections[current_section_data_index].data,current_section_size+word_size);
    *((uint16_t*)(&(elfFile.customSections[current_section_data_index].data[current_section_size])))=(uint16_t)num;
    current_section_size+=word_size;
}

void addWordSymbol(char* symbol_name,AddressingType addr_type)
{
    //PROSIRI SEKCIJU DA BI STAO WORD,UPISUJE SE 0 NA TA 2 BAJTA
    const int word_size = 2;
    elfFile.customSections[current_section_data_index].data=(uint8_t*)realloc(elfFile.customSections[current_section_data_index].data,current_section_size+word_size);
    *((uint16_t*)(&(elfFile.customSections[current_section_data_index].data[current_section_size])))=(uint16_t)0;

    addSymbolToPatchTable(symbol_name,current_section_size,addr_type);
    current_section_size+=word_size;
}

int symbolEntry(char* symbol_name)
{
    int string_table_size=elfFile.sectionHeaderTable[SECTION_NDX_STRTAB].sh_size;
    if(!string_table_size) return -2;   //NIJE JOS UVEK ALOCIRANA STRING SEKCIJA
    int string_section_data_entry=stringSectionDataEntry();
    int sym_tab_size=elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size/sizeof(Elf64_Sym);
    for(int z=0;z<sym_tab_size;z++)
    {
        int different=strcmp(&(elfFile.customSections[string_section_data_entry].data[elfFile.symtab[z].st_name]),symbol_name);
        if(!different)
        {
            return z;
        }
    }
    return -1;  //STRING SEKCIJA POSTOJI,ALI OVAJ SIMBOL NIJE DEFINISAN
}

void addSymbolToPatchTable(char* symbol_name,int program_counter,AddressingType addr_type)
{
    if(patchTable==NULL)patchTable=(PatchSymbol*)calloc(1,sizeof(PatchSymbol));
    for(int i=0;i<patchTableSize;i++)
    {
        int different=strcmp(patchTable[i].symbol_name,symbol_name);
        if(!different)
        {
            patchTable[i].locations=(struct SectionAndAddress*)realloc(patchTable[i].locations,(patchTable[i].number_of_locations+1)*sizeof(struct SectionAndAddress));
            struct SectionAndAddress x = {current_section_index,program_counter,addr_type};
            patchTable[i].locations[patchTable[i].number_of_locations]=x;
            patchTable[i].number_of_locations++;
            return;
        }
    }
    patchTable=(PatchSymbol*)realloc(patchTable,(patchTableSize+1)*sizeof(PatchSymbol));
    char* name = (char*)calloc(strlen(symbol_name)+1,sizeof(char));
    PatchSymbol y = {name,NULL,0};
    memcpy(name,symbol_name,strlen(symbol_name)+1);
    patchTable[patchTableSize] = y;
    patchTable[patchTableSize].locations=(struct SectionAndAddress*)calloc(1,sizeof(struct SectionAndAddress));
    struct SectionAndAddress x = {current_section_index,program_counter,addr_type};
    patchTable[patchTableSize].locations[0]=x;
    patchTable[patchTableSize].number_of_locations++;
    patchTableSize++;
}

void addExternSymbols(char* symbols)
{
    int i=stringSectionDataEntry();
    int string_table_size=elfFile.sectionHeaderTable[SECTION_NDX_STRTAB].sh_size;
    if(!string_table_size) {elfFile.customSections[i].data=(char*)calloc(1,sizeof(char));elfFile.customSections[i].data[0]='\0';string_table_size++;}
    char symbol_name[100];
    char* c=symbols;int j=0;
	while(1) {
        if(*c=='\n' || *c==' ' || *c=='\t')
        {
            c++;
            continue;
        }
	    if(*c==',' || *c=='\0')
        {
            symbol_name[j]='\0';
            //printf("[%s]",symbol_name);
            int sym_tab_size=elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size/sizeof(Elf64_Sym);
            for(int z=0;z<sym_tab_size;z++)
            {
                int different=strcmp(&(elfFile.customSections[i].data[elfFile.symtab[z].st_name]),symbol_name);
                if(!different)
                {
                    //EXTERN SIMBOL IMA NAJMANJI PRIORITET
                    break;
                }
                else
                {
                    if(z==sym_tab_size-1)
                    {
                        int strtab_entry;
                        //char* data = elfFile.customSections[i].data;
                        if(!(strtab_entry=getOffset(symbol_name, elfFile.customSections[i].data, string_table_size)))
                        {
                            elfFile.customSections[i].data = (char*)realloc(elfFile.customSections[i].data,(string_table_size+strlen(symbol_name)+1)*sizeof(char));
                            strtab_entry=string_table_size;
                            memcpy(&(elfFile.customSections[i].data[strtab_entry]),symbol_name,strlen(symbol_name)+1);
                            string_table_size+=strlen(symbol_name)+1;
                        }
                        int symtab_new_size = elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size+sizeof(Elf64_Sym);
                        elfFile.symtab = (Elf64_Sym*)realloc(elfFile.symtab,symtab_new_size);
                        Elf64_Sym y = {
                                    .st_name = strtab_entry,
                                    .st_info = ELF64_ST_INFO(EXTERN_UNUSED, STT_NOTYPE),
                                    .st_other = STV_DEFAULT,
                                    .st_shndx = SECTION_NDX_UNDEF,
                                    .st_value = 0x0000000000000000l,
                                    .st_size = 0,
                                };
                        elfFile.symtab[elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size/sizeof(Elf64_Sym)] = y;
                        elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size=symtab_new_size;
                    }
                }
            }
            j=0;
        }
        else
        {
            symbol_name[j]=*c;
            j++;
        }
        if(!(*c)) break;
        else c++;
	}
    elfFile.sectionHeaderTable[SECTION_NDX_STRTAB].sh_size = string_table_size;
}

void addGlobalSymbols(char* symbols) {
    int i=stringSectionDataEntry();
	
            int string_table_size=elfFile.sectionHeaderTable[SECTION_NDX_STRTAB].sh_size;
            if(!string_table_size) {elfFile.customSections[i].data=(char*)calloc(1,sizeof(char));elfFile.customSections[i].data[0]='\0';string_table_size++;}
            char symbol_name[100];
            char* c=symbols;int j=0;
	        while(1) {
                if(*c=='\n' || *c==' ' || *c=='\t')
                {
                    c++;
                    continue;
                }
		        if(*c==',' || *c=='\0')
                {
                    symbol_name[j]='\0';
                    int sym_tab_size=elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size/sizeof(Elf64_Sym);
                    for(int z=0;z<sym_tab_size;z++)
                    {
                        int different=strcmp(&(elfFile.customSections[i].data[elfFile.symtab[z].st_name]),symbol_name);
                        if(!different)
                        {
                            if(ELF64_ST_BIND(elfFile.symtab[z].st_info)==STB_LOCAL)
                            {
                                elfFile.symtab[z].st_info&=0x0F;
                                elfFile.symtab[z].st_info|=(STB_GLOBAL<<4);
                            }
                            else if(ELF64_ST_BIND(elfFile.symtab[z].st_info)==STB_GLOBAL || ELF64_ST_BIND(elfFile.symtab[z].st_info)==GLOBAL_UNDEFINED)
                            {
                                //DA LI JE GRESKA AKO SE 2 PUTA STAVI GLOBAL??
                            }
                            else if(ELF64_ST_BIND(elfFile.symtab[z].st_info)==EXTERN_UNUSED);
                            {
                                //PREGAZI GA,JER CE IME BITI ZAMASKIRANO LABELOM
                                elfFile.symtab[z].st_info&=0x0F;
                                elfFile.symtab[z].st_info|=GLOBAL_UNDEFINED<<4;
                            }
                            break;
                        }
                        else
                        {
                            if(z==sym_tab_size-1)
                            {
                                int strtab_entry;
                                //char* data = elfFile.customSections[i].data;
                                if(!(strtab_entry=getOffset(symbol_name, elfFile.customSections[i].data, string_table_size)))
                                {
                                    elfFile.customSections[i].data = (char*)realloc(elfFile.customSections[i].data,(string_table_size+strlen(symbol_name)+1)*sizeof(char));
                                    strtab_entry=string_table_size;
                                    memcpy(&(elfFile.customSections[i].data[strtab_entry]),symbol_name,strlen(symbol_name)+1);
                                    string_table_size+=strlen(symbol_name)+1;
                                }

                                int symtab_new_size = elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size+sizeof(Elf64_Sym);
                                elfFile.symtab = (Elf64_Sym*)realloc(elfFile.symtab,symtab_new_size);

                                Elf64_Sym y = {
                                            .st_name = strtab_entry,
                                            .st_info = ELF64_ST_INFO(GLOBAL_UNDEFINED, STT_NOTYPE),
                                            .st_other = STV_DEFAULT,
                                            .st_shndx = 0,
                                            .st_value = 0x0000000000000000l,
                                            .st_size = 0,
                                        };
                                elfFile.symtab[elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size/sizeof(Elf64_Sym)] = y;

                                elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size=symtab_new_size;
                            }
                        }
                    }
                    j=0;
                }
                else
                {
                    symbol_name[j]=*c;
                    j++;
                }
                if(!(*c)) break;
                else c++;
	        }

            elfFile.sectionHeaderTable[SECTION_NDX_STRTAB].sh_size = string_table_size;
}

int addNewSection(char* section_name) {
    //close current section
    elfFile.sectionHeaderTable[current_section_index].sh_size = current_section_size;

    //check if name already exists
    char* data = (char*)elfFile.customSections[0 /* prvi u nizu custom sections je shstrtab */ ].data;
    for(int i=0;i<elfFile.elfHeader.e_shnum;i++)
    {
        int shstrtab_entry = elfFile.sectionHeaderTable[i].sh_name;
        
        if(strcmp(section_name,&(data[shstrtab_entry]))==0)
        {
            //printf("SECTION %s ALREADY EXISTS\n",section_name);
            current_section_size=elfFile.sectionHeaderTable[i].sh_size;
            for(int j=0;j<elfFile.customSectionsLength;j++)
            {
                if(elfFile.customSections[j].sectionIndex==i)
                {
                    //printf("SECTION %s DATA WAS ALLOCATED\n",section_name);
                    current_section_data_index=j;
                    break;
                }
                else if(j==elfFile.customSectionsLength-1)
                {
                    //printf("SECTION %s DATA WAS NOT ALLOCATED\n",section_name);
                    int new_index = (elfFile.customSectionsLength)++;
                    elfFile.customSections=(CustomSection*)realloc(elfFile.customSections,(elfFile.customSectionsLength)*sizeof(CustomSection));
                    current_section_data_index=new_index;
                    elfFile.customSections[new_index].sectionIndex=i;
	                elfFile.customSections[new_index].data=(char*)calloc(0,sizeof(char));
                    break;
                }
            }
            return i;
        }
    }
    elfFile.sectionHeaderTable = (Elf64_Shdr*)realloc(elfFile.sectionHeaderTable,(elfFile.elfHeader.e_shnum+1)*sizeof(Elf64_Shdr));
    int shstrtab_entry;
    if(!(shstrtab_entry=getOffset(section_name, data, elfFile.sectionHeaderTable[SECTION_NDX_SHSTRTAB].sh_size)))
    {
        elfFile.customSections[0].data = (char*)realloc(elfFile.customSections[0].data,(elfFile.sectionHeaderTable[SECTION_NDX_SHSTRTAB].sh_size+strlen(section_name)+1)*sizeof(char));
        shstrtab_entry=elfFile.sectionHeaderTable[SECTION_NDX_SHSTRTAB].sh_size;
        memcpy(&(elfFile.customSections[0].data[shstrtab_entry]),section_name,strlen(section_name)+1);
        elfFile.sectionHeaderTable[SECTION_NDX_SHSTRTAB].sh_size+=strlen(section_name)+1;
    }

    Elf64_Shdr x = {
                .sh_name = shstrtab_entry,
                .sh_type = SHT_PROGBITS,
                .sh_flags = SHF_WRITE | SHF_ALLOC,
                .sh_addr = 0x0000000000000000l,
                .sh_offset = 0,
                .sh_size = 0,
                .sh_link = 0,
                .sh_info = 0,
                .sh_addralign = 1,
                .sh_entsize = 0,
            };
    elfFile.sectionHeaderTable[elfFile.elfHeader.e_shnum++] = x;

    int symtab_new_size = elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size+sizeof(Elf64_Sym);
    elfFile.symtab = (Elf64_Sym*)realloc(elfFile.symtab,symtab_new_size);

    Elf64_Sym y = {
                .st_name = 0,
                .st_info = ELF64_ST_INFO(STB_LOCAL, STT_SECTION),
                .st_other = STV_DEFAULT,
                .st_shndx = elfFile.elfHeader.e_shnum-1,
                .st_value = 0x0000000000000000l,
                .st_size = 0,
            };
    elfFile.symtab[elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size/sizeof(Elf64_Sym)] = y;

    elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size=symtab_new_size;

    //printf("SECTION %s DIDN'T EXIST AND SECTION DATA WAS NOT ALLOCATED\n",section_name);
    //ALOCIRAJ PROSTOR ZA PODATKE
    current_section_size = 0;
    int new_index = (elfFile.customSectionsLength)++;
    elfFile.customSections=(CustomSection*)realloc(elfFile.customSections,(elfFile.customSectionsLength)*sizeof(CustomSection));
    current_section_data_index=new_index;
    elfFile.customSections[new_index].sectionIndex=elfFile.elfHeader.e_shnum-1;
	elfFile.customSections[new_index].data=(char*)calloc(0,sizeof(char));


    return elfFile.elfHeader.e_shnum-1;
}

int getOffset(char *needle, char *haystack, int haystackLen)
{
    int needleLen = strlen(needle);
    char *search = haystack;
    int searchLen = haystackLen - needleLen + 1;
    for (; searchLen-- > 0; search++)
    {
        if (!memcmp(search, needle, needleLen))
        {
            return search - haystack;
        }
    }
    return 0;
}

void generateBasicSections() {
	elfFile.sectionHeaderTable=(Elf64_Shdr*)calloc(7,sizeof(Elf64_Shdr));
    Elf64_Shdr x [7] = {
            {
                .sh_name = 0,
                .sh_type = 0,
                .sh_flags = 0,
                .sh_addr = 0x0000000000000000l,
                .sh_offset = 0,
                .sh_size = 0,
                .sh_link = 0,
                .sh_info = 0,
                .sh_addralign = 0,
                .sh_entsize = 0,
            },
            {
                .sh_name = getOffset(".shstrtab", SHSTRTAB, SHSTRTAB_LENGTH),
                .sh_type = SHT_STRTAB,
                .sh_flags = 0,
                .sh_addr = 0x0000000000000000l,
                .sh_size = SHSTRTAB_LENGTH,
                .sh_link = 0,
                .sh_info = 0,
                .sh_addralign = 1,
                .sh_entsize = 0,
            },
            {
                .sh_name = getOffset(".strtab", SHSTRTAB, SHSTRTAB_LENGTH),
                .sh_type = SHT_STRTAB,
                .sh_flags = 0,
                .sh_addr = 0x0000000000000000l,
                .sh_offset = 0,
                .sh_size = 0,
                .sh_link = 0,
                .sh_info = 0,
                .sh_addralign = 1,
                .sh_entsize = 0,
            },
            {
                .sh_name = getOffset(".symtab", SHSTRTAB, SHSTRTAB_LENGTH), //na kom bajtu u tabeli naziva sekcija se nalazi ime ove sekcije
                .sh_type = SHT_SYMTAB,
                .sh_flags = 0,
                .sh_addr = 0x0000000000000000l,
                .sh_offset = 0,	//gde se tabela simbola nalazi u .o fajlu
                .sh_size = 4*sizeof(Elf64_Sym),	// velicina sekcije u bajtovima
                .sh_link = SECTION_NDX_STRTAB,      // indeks zaglavlja sekcije sa stringovima
                .sh_info = 0, // adresa za 1 veca od adrese poslednjeg lokalnog simbola
                .sh_addralign = 8,	//poravnanje
                .sh_entsize = sizeof(Elf64_Sym),	//velicina jednog ulaza (opisa jednog simbola)
            },
            {
                .sh_name = getOffset(".text", SHSTRTAB, SHSTRTAB_LENGTH),
                .sh_type = SHT_PROGBITS,
                .sh_flags = SHF_EXECINSTR | SHF_ALLOC,
                .sh_addr = 0x0000000000000000l,
                .sh_offset = 0,
                .sh_size = 0,
                .sh_link = 0,
                .sh_info = 0,
                .sh_addralign = 1,
                .sh_entsize = 0,
            },
            {
                .sh_name = getOffset(".data", SHSTRTAB, SHSTRTAB_LENGTH),
                .sh_type = SHT_PROGBITS,
                .sh_flags = SHF_WRITE | SHF_ALLOC,
                .sh_addr = 0x0000000000000000l,
                .sh_offset = 0,
                .sh_size = 0,
                .sh_link = 0,
                .sh_info = 0,
                .sh_addralign = 1,
                .sh_entsize = 0,
            },
            {
                .sh_name = getOffset(".bss", SHSTRTAB, SHSTRTAB_LENGTH),
                .sh_type = SHT_NOBITS,
                .sh_flags = SHF_WRITE | SHF_ALLOC,
                .sh_addr = 0x0000000000000000l,
                .sh_offset = 0,
                .sh_size = 0x00,
                .sh_link = 0,
                .sh_info = 0,
                .sh_addralign = 1,
                .sh_entsize = 0,
            }
    };
    int i;
    for(i=0;i<7;i++)
    {
        elfFile.sectionHeaderTable[i]=x[i];
    }
    elfFile.elfHeader.e_shnum=7;
    elfFile.elfHeader.e_shstrndx=SECTION_NDX_SHSTRTAB;
	elfFile.customSections=(CustomSection*)calloc(1,sizeof(CustomSection));
    elfFile.customSectionsLength++;
	elfFile.customSections[0].sectionIndex=1;
	elfFile.customSections[0].data=(char*)calloc(SHSTRTAB_LENGTH,sizeof(char));
	memcpy(elfFile.customSections[0].data,SHSTRTAB,SHSTRTAB_LENGTH);

    elfFile.symtab=(Elf64_Sym*)calloc(4,sizeof(Elf64_Sym));
    Elf64_Sym y[4] = {
            [SYMTAB_NDX_UNDEF] = {
                .st_name = 0,
                .st_info = ELF64_ST_INFO(STB_LOCAL, STT_NOTYPE),
                .st_other = STV_DEFAULT,
                .st_shndx = SECTION_NDX_UNDEF, // *UND*
                .st_value = 0x0000000000000000l,
                .st_size = 0,
            },
            [SYMTAB_NDX_TEXT] = {
                .st_name = 0,
                .st_info = ELF64_ST_INFO(STB_LOCAL, STT_SECTION),
                .st_other = STV_DEFAULT,
                .st_shndx = SECTION_NDX_TEXT,
                .st_value = 0x0000000000000000l,
                .st_size = 0,
            },
            [SYMTAB_NDX_DATA] = {
                .st_name = 0,
                .st_info = ELF64_ST_INFO(STB_LOCAL, STT_SECTION),
                .st_other = STV_DEFAULT,
                .st_shndx = SECTION_NDX_DATA,
                .st_value = 0x0000000000000000l,
                .st_size = 0,
            },
            [SYMTAB_NDX_BSS] = {
                .st_name = 0,
                .st_info = ELF64_ST_INFO(STB_LOCAL, STT_SECTION),
                .st_other = STV_DEFAULT,
                .st_shndx = SECTION_NDX_BSS,
                .st_value = 0x0000000000000000l,
                .st_size = 0,
            }
    };

    for(i=0;i<4;i++)
    {
        elfFile.symtab[i]=y[i];
    }

    addNewSection(".text");
}

int getSizeOfAllSections()
{
    int sum=0;
    for(int i=0;i<elfFile.elfHeader.e_shnum;i++)
    {
        sum+=elfFile.sectionHeaderTable[i].sh_size;
    }
    return sum;
}

void printElfFile()
{

    for(int j=0;j<elfFile.elfHeader.e_shnum;j++)
    {
        int data_index=-1;
        int rela_index=-1;
        for(int z=0;z<elfFile.customSectionsLength;z++)
        {
            if(elfFile.customSections[z].sectionIndex==j)
            {
                data_index=z;
            }
        }
        if(data_index==-1)
        {
            for(int z=0;z<elfFile.relaSectionsLength;z++)
            {
                if(elfFile.relaSections[z].sectionIndex==j)
                {
                    rela_index=z;
                }
            }
        }
        if(j==3)continue;
        if(data_index!=-1)
        {
            printf("START=(%d,%s,%d,%ld)\n",j,&(elfFile.customSections[0].data[elfFile.sectionHeaderTable[j].sh_name]),data_index,elfFile.sectionHeaderTable[j].sh_size);
            for(int i=0;i<elfFile.sectionHeaderTable[j].sh_size;i++)
            {
                printf("%x\n",elfFile.customSections[data_index].data[i]);
            }
            printf("FINISH");
        }
        else if(rela_index!=-1)
        {
            printf("START=(%d,%s,%d,%ld)\n",j,&(elfFile.customSections[0].data[elfFile.sectionHeaderTable[j].sh_name]),rela_index,elfFile.sectionHeaderTable[j].sh_size);
            for(int i=0;i<elfFile.sectionHeaderTable[j].sh_size/sizeof(Elf64_Rela);i++)
            {
                printf("[%lx,(%ld,%ld),%lx]\n",elfFile.relaSections[rela_index].data[i].r_offset,ELF64_R_SYM(elfFile.relaSections[rela_index].data[i].r_info),ELF64_R_TYPE(elfFile.relaSections[rela_index].data[i].r_info),elfFile.relaSections[rela_index].data[i].r_addend);
            }
            printf("FINISH");
        }
    }

    printf("TABELA SIMBOLA\n");
    for(int j=0;j<elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size/sizeof(Elf64_Sym);j++)
    {
        Elf64_Sym temp=elfFile.symtab[j];
        printf("%s,%x,%d,%ld\n",&(elfFile.customSections[stringSectionDataEntry()].data[temp.st_name]),temp.st_info,temp.st_shndx,temp.st_value);
    }
    printf("KRAJ TABELE SIMBOLA");
}

void finishAssembling()
{
    elfFile.sectionHeaderTable[current_section_index].sh_size = current_section_size;
    
    //PATCH SYMBOLS
    int sym_tab_size=elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size/sizeof(Elf64_Sym);
    for(int i=0;i<patchTableSize;i++)
    {
        char* symbol_name=patchTable[i].symbol_name;
        int symbol_index=-1;
        for(int j=0;j<sym_tab_size;j++)
        {
            //printf("{%s==%s}\n",&(elfFile.customSections[stringSectionDataEntry()].data[elfFile.symtab[j].st_name]),symbol_name);
            int different=strcmp((ELF32_ST_TYPE(elfFile.symtab[j].st_info) != STT_SECTION)?(&(elfFile.customSections[stringSectionDataEntry()].data[elfFile.symtab[j].st_name])):(&(elfFile.customSections[0].data[elfFile.sectionHeaderTable[elfFile.symtab[j].st_shndx].sh_name])),symbol_name);
            if(!different)
            {
                symbol_index=j;
                break;
            }
        }
        if(symbol_index==-1)
        {
            printf("There is symbol (%s) which is not defined!",symbol_name);
            exit(3);
        }
        if(elfFile.symtab[symbol_index].st_info>>4==EXTERN_UNUSED)
        {
            elfFile.symtab[symbol_index].st_info&=0x0F;
            elfFile.symtab[symbol_index].st_info|=STB_GLOBAL<<4;
        }
        else if(elfFile.symtab[symbol_index].st_info>>4==GLOBAL_UNDEFINED)
        {
            elfFile.symtab[symbol_index].st_info&=0x0F;
            elfFile.symtab[symbol_index].st_info|=STB_GLOBAL<<4;
        }
        for(int j=0;j<patchTable[i].number_of_locations;j++)
        {
            int section_entry=-1;
            int isGlobal=ELF64_ST_BIND(elfFile.symtab[symbol_index].st_info)==STB_GLOBAL;
            int section_symbol_index;
            if(!isGlobal) {
                section_entry=elfFile.symtab[symbol_index].st_shndx;
                for(int z=0;z<sym_tab_size;z++)
                {
                    if (elfFile.symtab[z].st_shndx == section_entry && ELF32_ST_TYPE(elfFile.symtab[z].st_info) == STT_SECTION)
                    {
                      section_symbol_index=z;
                      break;
                    }
                    if(z==sym_tab_size-1)
                    {
                        printf("Error!\n");
                        exit(41);
                    }
                }
            }

            if(patchTable[i].locations[j].addr_type==IMMEDIATE)
            {
                Elf64_Rela y = {
                    .r_offset = patchTable[i].locations[j].address,
                    .r_info = ELF64_R_INFO(isGlobal?symbol_index:section_symbol_index,R_X86_64_16),
                    .r_addend = isGlobal?0x0000000000000000l:(elfFile.symtab[symbol_index].st_value),
                };
                setRecordInRelaSection(y,patchTable[i].locations[j].section_entry);
            }
            else if(patchTable[i].locations[j].addr_type==PC_RELATIVE)
            {
                //AKO JE DESTINACIJA U ISTOJ SEKCIJI,NE TREBA RELACIONI ZAPIS
                if(patchTable[i].locations[j].section_entry==elfFile.symtab[symbol_index].st_shndx)
                {
                    int data_entry=getCustomSectionDataEntry(patchTable[i].locations[j].section_entry);
                    if(data_entry==-1)
                    {
                        printf("Error!\n");
                        exit(6);
                    }
                    *((uint16_t*)(&elfFile.customSections[data_entry].data[patchTable[i].locations[j].address]))=elfFile.symtab[symbol_index].st_value-(patchTable[i].locations[j].address+2);
                    continue;
                }

                Elf64_Rela y = {
                    .r_offset = patchTable[i].locations[j].address,
                    .r_info = ELF64_R_INFO(isGlobal?symbol_index:section_symbol_index,R_X86_64_PC16),
                    .r_addend = isGlobal?-2:(elfFile.symtab[symbol_index].st_value-2),
                };
                setRecordInRelaSection(y,patchTable[i].locations[j].section_entry);
            }
            else
            {
                printf("Addresing error!\n");
                exit(4);
            }
        }
        free(patchTable[i].symbol_name);
        free(patchTable[i].locations);
    }
    free(patchTable);

    //CORRECT BINDINGS IN SYMBOL_TABLE(MOZDA NI NE MORA)

    //WRITE ELF STRUCT IN FILE
    int out_file_length=strlen(out_file);
    char* txt_file=(char*)(calloc(out_file_length+1,sizeof(char)));
    strcpy(txt_file,out_file);
    txt_file[out_file_length-1]='t';
    // txt_file[out_file_length-2]='x';
    // txt_file[out_file_length-3]='t';

    int cursor=0;
    remove(out_file);remove(txt_file);
    FILE *fileHandle = fopen(out_file, "a");
    FILE *fileHandleTxt = fopen(txt_file, "a");
    if (fileHandle != NULL && fileHandleTxt!=NULL)
    {
        elfFile.elfHeader.e_shoff=sizeof(Elf64_Ehdr)+getSizeOfAllSections();
        fwrite(&elfFile.elfHeader, sizeof(elfFile.elfHeader), 1, fileHandle);
        // char* char_repr=(char*)(&elfFile.elfHeader);
        // for(int i=0;i<sizeof(elfFile.elfHeader);i++)
        // { 
        //     fprintf(fileHandleTxt,"%c",*(char_repr+i));
        // }
        cursor+=sizeof(Elf64_Ehdr);
        for(int i=0;i<elfFile.elfHeader.e_shnum;i++)
        {
            int type=elfFile.sectionHeaderTable[i].sh_type;

            //NE ZNAM DA LI JE U REDU DA OFFSET POSTAVIM ZA SEKCIJE CIJA JE VELICINA 0
            elfFile.sectionHeaderTable[i].sh_offset=cursor;
            if(type==SHT_NULL)
            {
                continue;
            }
            else if(type==SHT_PROGBITS || type==SHT_STRTAB || type==SHT_NOBITS)
            {
                for(int j=0;j<elfFile.customSectionsLength;j++)
                {
                    if(elfFile.customSections[j].sectionIndex==i)
                    {
                        fwrite(elfFile.customSections[j].data, elfFile.sectionHeaderTable[i].sh_size, 1, fileHandle);
                        uint8_t* char_repr=elfFile.customSections[j].data;
                        fprintf(fileHandleTxt,"\n%s\n",&(elfFile.customSections[0].data[elfFile.sectionHeaderTable[i].sh_name]));
                        for(int z=0;z<elfFile.sectionHeaderTable[i].sh_size;z++)
                        { 
                            fprintf(fileHandleTxt,"%02x ",*(char_repr+z));
                            if(z%8==7) fprintf(fileHandleTxt,"%c",'\n');
                        }
                    }
                }
            }
            else if(type==SHT_SYMTAB)
            {
                fwrite(elfFile.symtab, elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size, 1, fileHandle);
                //char* char_repr=(char*)(elfFile.symtab);
                fprintf(fileHandleTxt,"\nSymtab (Name,Info,Section,Value)\n");
                for(int j=0;j<elfFile.sectionHeaderTable[SECTION_NDX_SYMTAB].sh_size/sizeof(Elf64_Sym);j++)
                { 
                    char* symbol_name;
                    Elf64_Sym temp=elfFile.symtab[j];
                    if( ELF32_ST_TYPE(temp.st_info)==STT_SECTION)
                    {
                        symbol_name=&(elfFile.customSections[0].data[elfFile.sectionHeaderTable[temp.st_shndx].sh_name]);
                    }
                    else
                    {
                        symbol_name=&(elfFile.customSections[stringSectionDataEntry()].data[temp.st_name]);
                    }
                    fprintf(fileHandleTxt,"%s,%x,%d(%s),%ld\n",symbol_name,temp.st_info,temp.st_shndx,&(elfFile.customSections[0].data[elfFile.sectionHeaderTable[temp.st_shndx].sh_name]),temp.st_value);
                }
            }
            else if(type==SHT_RELA)
            {
                for(int j=0;j<elfFile.relaSectionsLength;j++)
                {
                    if(elfFile.relaSections[j].sectionIndex==i)
                    {
                        fwrite(elfFile.relaSections[j].data, elfFile.sectionHeaderTable[i].sh_size, 1, fileHandle);
                        //char* char_repr=(char*)(elfFile.relaSections[j].data);
                        fprintf(fileHandleTxt,"\n%s [Offset,(Symbol,Type),Addend]\n",&(elfFile.customSections[0].data[elfFile.sectionHeaderTable[i].sh_name]));
                        for(int z=0;z<elfFile.sectionHeaderTable[i].sh_size/sizeof(Elf64_Rela);z++)
                        {
                            Elf64_Rela temp=elfFile.relaSections[j].data[z];
                            fprintf(fileHandleTxt,"[%lx,(%ld,%ld),%lx]\n",temp.r_offset,ELF64_R_SYM(temp.r_info),ELF64_R_TYPE(temp.r_info),temp.r_addend);
                        }
                    }
                }
            }

            cursor+=elfFile.sectionHeaderTable[i].sh_size;
        }
        fwrite(elfFile.sectionHeaderTable, sizeof(Elf64_Shdr), elfFile.elfHeader.e_shnum, fileHandle);
        fprintf(fileHandleTxt,"\nSection header table [Name,Size]\n");
        for(int z=0;z<elfFile.elfHeader.e_shnum;z++)
        {
            Elf64_Shdr temp=elfFile.sectionHeaderTable[z];
            fprintf(fileHandleTxt,"[%s,%ld]\n",&(elfFile.customSections[0].data[temp.sh_name]),temp.sh_size);
        }
    }

    //ISPIS ELF-A
    //printElfFile();

    //FREE DYNAMIC MEMORY
    if(fileHandle)fclose(fileHandle);
    if(fileHandleTxt)fclose(fileHandleTxt);
    for(int i=0;i<elfFile.customSectionsLength;i++)
    {
        free(elfFile.customSections[i].data);
    }
    free(elfFile.customSections);
    free(elfFile.symtab);
    for(int i=0;i<elfFile.relaSectionsLength;i++)
    {
        free(elfFile.relaSections[i].data);
    }
    free(elfFile.relaSections);
    free(elfFile.sectionHeaderTable);
    
}

int main (int argc,char* argv[]) {
    if(argc!=4 || strcmp(argv[1],"-o"))
    {
        printf("Wrong format! Expected format: asembler -o out_file in_file \n");
        exit(1);
    }
    else
    {
	    yyin=fopen(argv[3],"r");
        out_file=argv[2];
	    if(yyin==NULL)
	    {
	    	printf("File error!\n");
	    }
	    else
	    {
	    	generateBasicSections();
	    	int status = yyparse ( );

	    	fclose(yyin);
            //printf("Asembler end\n");
	    	return status;
	    }
    }
    
}

void yyerror (char *s) {fprintf (stderr, "%s\n", s);fprintf(stderr,"%s\n","TTTT");} 
